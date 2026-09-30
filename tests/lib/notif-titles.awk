# tests/lib/notif-titles.awk — the page titles the daemons send, read from their source, for CI's facts step "every
# page is named in docs/NOTIFICATIONS.md" (.github/workflows/ci.yml; the rule is written there). POSIX awk: mawk, gawk
# and BWK awk; no {m,n} interval anywhere.
#   usage: awk -f tests/lib/notif-titles.awk A B A B     (every file TWICE: pass 1 finds the wrappers, pass 2 the calls)
# Output, one TAB-separated row per call:
#   T <file:line> status|heading <title>   a title read as a literal: an `alert` call's status (its third argument,
#                                          verbatim), or an `alert_warn` message's heading (its leading literal text, up
#                                          to the first $ or ` expansion, trailing blanks dropped; the whole message when
#                                          it has none)
#   U <file:line> status|heading <why>     a call whose title cannot be read as a literal: an expansion in the status,
#                                          no literal text before the message's first expansion, a quote left open at
#                                          the end of the line (a multi-line call), fewer arguments
#   W <function> alert|alert_warn <$N>     a WRAPPER: a function whose body passes its own "$N" as an alert call's status
#                                          or as an alert_warn message; its callers' Nth argument is read as that title
#   N <file:line> info <heading>           an alert_info call (Telegram-only, OUTSIDE the check): its heading, same rule
#   I <count>                              the number of alert_info calls
#   X <file:line> <why>                    a function defined in another shape than `name() {` at column 0: a wrapper
#                                          there would go unseen, so the facts step is red on it
# How a line is read: comment-only and blank lines are skipped; quotes are tracked (' and ", and $( … ) inside "), so a
# call word counts only as a COMMAND word of code — at the start of the line or after ; & | { } ( ) ! or then / do /
# else / if / elif / while / until / time — never inside a string or after a # comment. A function is `name() {` at
# column 0 and ends at a `}` at column 0 (every function in both daemons is written that way).
function scanargs(s, i,    n, c, st, dep, arg, lit, fx, q) {
    # reads up to 3 arguments of the call from s at i: AR[k] the text, AL[k] 1 when it is a literal, FX[k] the index in
    # AR[k] where its first expansion starts (0: none); open = 1 when a quote runs past the end of the line
    na = 0; open = 0; n = length(s)
    while (na < 3) {
        while (i <= n && substr(s, i, 1) ~ /[ \t]/) i++
        if (i > n) return
        c = substr(s, i, 1)
        if (c ~ /[;&|)}#<>]/) return
        arg = ""; lit = 1; fx = 0; st = ""; dep = 0
        while (i <= n) {
            c = substr(s, i, 1)
            if (st == "") {
                if (c ~ /[ \t;&|)}<>]/) break
                if (c == "\047") { st = "S"; i++; continue }
                if (c == "\"") { st = "D"; i++; continue }
                if (c == "\\") { arg = arg substr(s, i + 1, 1); i += 2; continue }
                if (c == "$" || c == "`") { lit = 0; if (!fx) fx = length(arg) + 1 }
                arg = arg c; i++; continue
            }
            if (st == "S") { if (c == "\047") { st = ""; i++; continue } arg = arg c; i++; continue }
            if (st == "D") {
                if (c == "\\") { q = substr(s, i + 1, 1); if (q !~ /["\\$`]/) arg = arg c; arg = arg q; i += 2; continue }
                if (c == "\"") { st = ""; i++; continue }
                if (c == "$" || c == "`") { lit = 0; if (!fx) fx = length(arg) + 1 }
                if (c == "$" && substr(s, i + 1, 1) == "(") { st = "X"; dep = 1; arg = arg "$("; i += 2; continue }
                arg = arg c; i++; continue
            }
            if (st == "X") {                              # inside "…$( … )…": only its parentheses matter here
                if (c == "(") dep++
                else if (c == ")") { dep--; if (dep == 0) st = "D" }
                arg = arg c; i++; continue
            }
        }
        na++; AR[na] = arg; AL[na] = lit; FX[na] = fx
        if (st != "") { open = 1; AL[na] = 0; return }
    }
}
function heading(k,    m) { m = AR[k]; if (FX[k]) m = substr(m, 1, FX[k] - 1); sub(/[ \t]+$/, "", m); return m }
function row(kind, k, who,    h) {                   # the T or U row for argument k of the call just scanned
    if (open && na <= k) { printf "U\t%s\t%s\t%sa quote left open at the end of the line (a multi-line call)\n", at, kind, who; return }
    if (na < k) { printf "U\t%s\t%s\t%sfewer than %d argument(s)\n", at, kind, who, k; return }
    if (kind == "status") {
        if (!AL[k]) printf "U\t%s\t%s\t%sthe status is not a literal: %s\n", at, kind, who, AR[k]
        else printf "T\t%s\t%s\t%s\n", at, kind, AR[k]
        return
    }
    h = heading(k)
    if (h == "") printf "U\t%s\t%s\t%sno literal text before the message's first expansion: %s\n", at, kind, who, substr(AR[k], 1, 60)
    else printf "T\t%s\t%s\t%s\n", at, kind, h
}
function calls(s,    n, i, c, st, dep, w, cmdpos, j) {  # the COMMAND words of one line: CW[1..nc], CP[k] = the index past it
    nc = 0; n = length(s); st = ""; cmdpos = 1; i = 1
    while (i <= n) {
        c = substr(s, i, 1)
        if (st == "S") { if (c == "\047") st = ""; i++; continue }
        if (st == "D") {
            if (c == "\\") { i += 2; continue }
            if (c == "\"") { st = ""; i++; continue }
            if (c == "$" && substr(s, i + 1, 1) == "(") { st = "X"; dep = 1; i += 2; continue }
            i++; continue
        }
        if (st == "X") { if (c == "(") dep++; else if (c == ")") { dep--; if (dep == 0) st = "D" } i++; continue }
        if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t]/)) return
        if (c == "\047") { st = "S"; cmdpos = 0; i++; continue }
        if (c == "\"") { st = "D"; cmdpos = 0; i++; continue }
        if (c == "\\") { cmdpos = 0; i += 2; continue }
        if (c ~ /[;&|{}()!]/) { cmdpos = 1; i++; continue }
        if (c ~ /[ \t]/) { i++; continue }
        if (c ~ /[A-Za-z_]/) {
            j = i; while (j <= n && substr(s, j, 1) ~ /[A-Za-z0-9_]/) j++
            w = substr(s, i, j - i)
            if (cmdpos && (j > n || substr(s, j, 1) ~ /[ \t]/)) { nc++; CW[nc] = w; CP[nc] = j }
            cmdpos = (w ~ /^(then|do|else|if|elif|while|until|time)$/ && (j > n || substr(s, j, 1) ~ /[ \t;]/)) ? 1 : 0
            i = j; continue
        }
        cmdpos = 0; i++
    }
}
FNR == 1 { if (first == "") { first = FILENAME; pass = 1 } else if (FILENAME == first) pass = 2; fn = ""; base = FILENAME; sub(/.*\//, "", base) }
/^[ \t]*#/ || /^[ \t]*$/ { next }
/^[ \t]*(function[ \t]+)?[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)/ && !/^[A-Za-z_][A-Za-z0-9_]*\(\)[ \t]*\{/ {
    if (pass == 2) printf "X\t%s:%d\ta function defined in another shape than `name() {` at column 0 (its wrapper calls would go unseen)\n", base, FNR
}
/^[A-Za-z_][A-Za-z0-9_]*\(\)[ \t]*\{/ { fn = $0; sub(/\(.*/, "", fn) }
/^\}/ { fn = "" }
{
    calls($0); at = base ":" FNR
    for (k = 1; k <= nc; k++) {
        w = CW[k]
        if (w != "alert" && w != "alert_warn" && w != "alert_info" && !(w in WR)) continue
        scanargs($0, CP[k])
        if (w == "alert_info") { if (pass == 2) { ninfo++; h = (na >= 1 && !open) ? heading(1) : ""; printf "N\t%s\tinfo\t%s\n", at, (h == "" ? "(no literal heading)" : h) } continue }
        if (w == "alert" || w == "alert_warn") {
            pos = (w == "alert") ? 3 : 1
            if (na >= pos && AR[pos] ~ /^\$([1-9]|\{[1-9]\})$/ && fn != "") {       # the wrapper's own forward
                if (pass == 1) { WR[fn] = w; WA[fn] = AR[pos]; gsub(/[^0-9]/, "", WA[fn]); WA[fn] += 0; printf "W\t%s\t%s\t%s\n", fn, w, AR[pos] }
                continue
            }
            if (pass == 2) row((w == "alert") ? "status" : "heading", pos, "")
            continue
        }
        if (pass == 2) row((WR[w] == "alert") ? "status" : "heading", WA[w], w ": ")   # a wrapper's caller
    }
    if ($0 ~ /^[A-Za-z_][A-Za-z0-9_]*\(\)[ \t]*\{.*\}[ \t]*$/) fn = ""           # a one-line function ends on its line
}
END { printf "I\t%d\n", ninfo + 0 }
