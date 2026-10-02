# tests/lib/notif-titles.awk — the page titles the daemons send, read from their source, for CI's facts step "every
# page is named in docs/NOTIFICATIONS.md" (.github/workflows/ci.yml; the rule is written there). POSIX awk: mawk, gawk,
# busybox and BWK awk; no {m,n} interval anywhere.
#   usage: awk -f tests/lib/notif-titles.awk A B A B     (every file TWICE: pass 1 finds the wrappers, pass 2 the calls)
# Output, one TAB-separated row per call:
#   T <file:line> status|heading|direct|webhook <title>   a title read as a literal: an `alert` call's status (its third
#                                          argument, verbatim), an `alert_warn` message's heading, a direct
#                                          `send_telegram`'s heading (its first argument), or a direct `send_webhook`'s
#                                          title (its THIRD argument, the status its receiver shows as the title,
#                                          verbatim) — a heading is the message's leading literal text, up to the first $
#                                          or ` expansion, trailing blanks dropped (the whole message when it has none)
#   U <file:line> status|heading|direct|webhook|call <why>   UNREADABLE: an expansion in a status or a webhook title; a
#                                          title with fewer than 10 letters or digits (A-Z a-z 0-9) beyond its emoji and
#                                          punctuation (an empty heading included); a quote left open at the end of the line
#                                          (a multi-line call); a line ending in a backslash (a call continued on the next
#                                          line); fewer arguments; a call word with any quoted part — '…', "…", $'…', $"…" —
#                                          or a backslash in it, read as bash reads it after quote removal (al"ert", "alert"
#                                          and $'alert' are the word alert); a command word holding an ANSI-C escape ($'\…')
#                                          this reader does not decode; and — fail-closed — the word alert, alert_warn,
#                                          send_telegram, send_webhook or a wrapper's name standing in the code as an
#                                          unquoted word where no call was read (an argument: behind eval / command / exec /
#                                          a pipe tool; a name inside a $(( … )); a definition in another shape …); and a
#                                          line the reader ends inside a level it opened — a ${ … }, a $(( … )) or a "…",
#                                          or a $( … ) or backticks unless a backslash continues the line (the daemons'
#                                          `x=$(curl … \` lines): a construct spanning lines, or a line the reader lost
#                                          its place on — a call after that point would go unread
#   W <function> alert|alert_warn|direct|webhook <$N>   a WRAPPER: a function whose body passes its own "$N" as an alert
#                                          call's status, an alert_warn message, a direct send_telegram's message or a
#                                          direct send_webhook's title; its callers' Nth argument is read as that title
#   N <file:line> info <heading>           an alert_info call (Telegram-only, OUTSIDE the check): its heading, same rule
#   I <count>                              the number of alert_info calls
#   X <file:line> <why>                    a function defined in another shape than `name() {` at column 0: a wrapper
#                                          there would go unseen, so the facts step is red on it
# How a line is read: comment-only and blank lines are skipped; the code is lexed into shell words with its quoting
# (' " \ $'…' $"…"), the literal text of a double-quoted part joining its word as bash's quote removal joins it; its
# $( … ) and backticks are read as CODE at any depth — inside a double-quoted "…", an unquoted ${ … } or $(( … )), and an
# array value NAME=( … ) included; a $(( … )) is the same level quoted or not (a name in it as above); a ${ … } ends at
# its first } that is not quoted, escaped or inside a level it opened, as bash ends it (a bare { in it is text); a command
# word is the first word of a simple command — after ; & | { } ( ) ! or then / do / else / if / elif / while / until /
# time (and time's -p and --), and PAST any assignment words (NAME=… NAME+=… NAME[…]=…) and redirections (n> > >> < <<<
# &> n>&m and their target words) that precede it. A # starts a comment only at a word's start. A function is
# `name() {` at column 0 and ends at a `}` at column 0 (every function in both daemons is written that way). The sends
# inside the four SINKS — alert, alert_warn, alert_info, flush_pending_alerts — are the transport of their callers'
# pages (read at the callers), not pages of their own. LIMIT (named): the reader is line-based (a here-document body is
# read as code; a construct spanning lines is read up to the line's end — the U row above), a backslash-escaped backtick
# inside backticks (a nested command substitution in the old spelling, `… \`cmd\` …`) is read as a quoted character, not
# as code (the daemons have no backtick in their code; the parse censuses name the same shape), and a command word
# assembled at run time ($f, "$cmd") or a call in a string that eval or trap runs is not seen — the (7g)-style parse
# censuses are the tool for those shapes, not this doc check.
BEGIN {
    MINL = 10
    SINK["alert"] = 1; SINK["alert_warn"] = 1; SINK["alert_info"] = 1; SINK["flush_pending_alerts"] = 1
}
function nletters(t,    c) { c = t; return gsub(/[A-Za-z0-9]/, "", c) }
function watched(w) { return (w == "alert" || w == "alert_warn" || w == "alert_info" || w == "send_telegram" || w == "send_webhook" || (w in WR)) }
function scanargs(s, i, closer,    n, c, st, dep, arg, lit, fx, q, isfd) {
    # reads up to 3 arguments of the call from s at i: AR[k] the text, AL[k] 1 when it is a literal, FX[k] the index in
    # AR[k] where its first expansion starts (0: none); open = 1 when a quote runs past the end of the line. It stops at
    # an operator, a redirection (n> < > &>), a comment, the end of the call's $( ) (a ")") or its backticks (closer "`")
    na = 0; open = 0; n = length(s)
    while (na < 3) {
        while (i <= n && substr(s, i, 1) ~ /[ \t]/) i++
        if (i > n) return
        c = substr(s, i, 1)
        if (c ~ /[;&|)}#<>]/ || (closer == "`" && c == "`")) return
        arg = ""; lit = 1; fx = 0; st = ""; dep = 0; isfd = 1
        while (i <= n) {
            c = substr(s, i, 1)
            if (st == "") {
                if (c ~ /[ \t;&|)}<>]/ || (closer == "`" && c == "`")) break
                if (c !~ /[0-9]/) isfd = 0
                if (c == "\047") { st = "S"; i++; continue }
                if (c == "\"") { st = "D"; i++; continue }
                if (c == "\\") { arg = arg substr(s, i + 1, 1); i += 2; continue }
                if (c == "$" || c == "`") { lit = 0; if (!fx) fx = length(arg) + 1 }
                arg = arg c; i++; continue
            }
            isfd = 0
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
        if (st == "" && isfd && arg != "" && substr(s, i, 1) ~ /[<>]/) return   # "2>" — a redirection, not an argument
        na++; AR[na] = arg; AL[na] = lit; FX[na] = fx
        if (st != "") { open = 1; AL[na] = 0; return }
    }
}
function heading(k,    m) { m = AR[k]; if (FX[k]) m = substr(m, 1, FX[k] - 1); sub(/[ \t]+$/, "", m); return m }
function row(kind, k, who,    h) {                   # the T or U row for argument k of the call just scanned
    if (cont) { printf "U\t%s\t%s\t%sa line ending in a backslash (a call continued on the next line)\n", at, kind, who; return }
    if (open && na <= k) { printf "U\t%s\t%s\t%sa quote left open at the end of the line (a multi-line call)\n", at, kind, who; return }
    if (na < k) { printf "U\t%s\t%s\t%sfewer than %d argument(s)\n", at, kind, who, k; return }
    if (kind == "status" || kind == "webhook") {      # read whole: an alert's status, a direct send_webhook's title
        if (!AL[k]) printf "U\t%s\t%s\t%sthe %s is not a literal: %s\n", at, kind, who, (kind == "status") ? "status" : "webhook title", AR[k]
        else if (nletters(AR[k]) < MINL) printf "U\t%s\t%s\t%sfewer than %d letters or digits in the %s: %s\n", at, kind, who, MINL, (kind == "status") ? "status" : "webhook title", AR[k]
        else printf "T\t%s\t%s\t%s\n", at, kind, AR[k]
        return
    }
    h = heading(k)
    if (h == "") printf "U\t%s\t%s\t%sno literal text before the message's first expansion: %s\n", at, kind, who, substr(AR[k], 1, 60)
    else if (nletters(h) < MINL) printf "U\t%s\t%s\t%sfewer than %d letters or digits in the heading: %s\n", at, kind, who, MINL, h
    else printf "T\t%s\t%s\t%s\n", at, kind, h
}
# The lexer's levels: C — code (CLO its closer: "" the line, ")" a $( … ) / ( … ) value, "`" backticks); D — a
# double-quoted "…" (WL: the level whose word its literal text joins, 0 for none); P — an unquoted ${ … }, ended by its
# first } (bash counts no bare { in it); A — a $(( … )) (PA its open parentheses). In D, P and A a $( … ) or backticks
# open a C level, a $(( … )) an A level; in P and A a ${ … } opens a P level.
function pushc(closer) { sp++; TY[sp] = "C"; CLO[sp] = closer; PD[sp] = 0; CPOS[sp] = 1; RDT[sp] = 0; INW[sp] = 0; TP[sp] = 0 }
function pushd(wl) { sp++; TY[sp] = "D"; WL[sp] = wl; INW[sp] = 0 }
function pushp() { sp++; TY[sp] = "P"; INW[sp] = 0 }
function pusha() { sp++; TY[sp] = "A"; PA[sp] = 0; INW[sp] = 0 }
function wstart(i) { if (!INW[sp]) { INW[sp] = 1; WS[sp] = i; WT[sp] = ""; WQ[sp] = 0; WX[sp] = 0; WE[sp] = 0 } }
function endword(s, i,    w, j, isdef, isasg, tp) {  # the word that ends at i (exclusive) at level sp: a call, a mention, …
    if (!INW[sp]) return
    INW[sp] = 0; w = WT[sp]
    if (RDT[sp]) { RDT[sp] = 0; return }                                   # a redirection's target: the position stays
    isasg = (substr(s, WS[sp]) ~ /^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=/)
    if (CPOS[sp] && isasg) return                                          # an assignment word before the command word
    j = i; while (j <= length(s) && substr(s, j, 1) ~ /[ \t]/) j++
    isdef = (substr(s, j, 2) == "()" || substr(s, j, 3) == "( )")
    if (FNKW) { FNKW = 0; isdef = 1 }                                     # the name after `function`
    if (CPOS[sp]) {
        tp = TP[sp]; TP[sp] = (!WQ[sp] && !WX[sp] && (w == "time" || (tp && w == "-p")))   # time, then its -p and --
        CPOS[sp] = (!WQ[sp] && !WX[sp] && (w ~ /^(then|do|else|if|elif|while|until|time|!)$/ || (tp && w ~ /^(-p|--)$/)))
        if (!WQ[sp] && !WX[sp] && w == "function") { FNKW = 1; return }
        if (isdef || WX[sp]) return
        if (WE[sp]) { ne++; EW[ne] = w; return }                          # $'\x61lert' — an escape this reader does not decode
        if (!watched(w)) return
        if (WQ[sp]) { if (w != "alert_info") { nq++; QW[nq] = w } return }  # 'alert' "alert" al"ert" $'alert' \alert — a quoted call word
        nc++; CW[nc] = w; CP[nc] = i; CC[nc] = CLO[sp]; return
    }
    if (!WQ[sp] && !WX[sp] && !isdef && watched(w) && w != "alert_info") { nm++; MW[nm] = w }   # a mention: no call read
}
function inner(s, i, c,    d) {   # in a D, P or A level: a $( ), backticks, ${ } or $(( )) at i opens its level — returns
                                  # the index past its opener, 0 when none opens there
    if (c == "`") { pushc("`"); return i + 1 }
    if (c != "$") return 0
    d = substr(s, i + 1, 1)
    if (d == "(" && substr(s, i + 2, 1) == "(") { pusha(); return i + 3 }
    if (d == "(") { pushc(")"); return i + 2 }
    if (d == "{") { pushp(); return i + 2 }
    return 0
}
function lost(s,    k) {   # the line ends (or a quote runs past its end) with level sp open: LOST names the innermost level
                           # the reader opened that is still open — any ${ … }, $(( … )) or "…"; a $( … ) or backticks unless
                           # a backslash continues the line — "" when none is
    for (k = sp; k > 1; k--) {
        if (TY[k] == "C" && s ~ /\\$/) continue
        if (TY[k] == "P") LOST = "${ … }"; else if (TY[k] == "A") LOST = "$(( … ))"; else if (TY[k] == "D") LOST = "\"…\""; else LOST = "$( … ) or backticks"
        return
    }
}
function calls(s,    n, i, c, d, k, op) {           # the calls on one line: CW[1..nc] (CP past the word, CC its closer)
    nc = 0; nm = 0; nq = 0; ne = 0; n = length(s); i = 1; FNKW = 0; LOST = ""
    sp = 1; TY[1] = "C"; CLO[1] = ""; PD[1] = 0; CPOS[1] = 1; RDT[1] = 0; INW[1] = 0; TP[1] = 0
    while (i <= n) {
        c = substr(s, i, 1)
        if (TY[sp] == "D") {                                               # "…": text — it joins its word (quote removal, as
            k = WL[sp]                                                     # bash does) — but $( ) and backticks are code
            if (c == "\\") { d = substr(s, i + 1, 1); if (k) WT[k] = WT[k] ((d ~ /[$`"\\]/) ? d : c d); i += 2; continue }
            if (c == "\"") { sp--; i++; continue }
            if (c == "$" && substr(s, i + 1, 1) == "$") { if (k) { WX[k] = 1; WT[k] = WT[k] "$$" } i += 2; continue }
            if (c == "$" && substr(s, i + 1, 1) == "(") { if (k) WX[k] = 1; if (substr(s, i + 2, 1) == "(") { pusha(); i += 3 } else { pushc(")"); i += 2 } continue }
            if (c == "`") { if (k) WX[k] = 1; pushc("`"); i++; continue }
            if (k) { if (c == "$") WX[k] = 1; WT[k] = WT[k] c }
            i++; continue
        }
        if (TY[sp] == "P" || TY[sp] == "A") {                              # an unquoted ${ … } or a $(( … )): text and names —
            if (c == "\\") { i += 2; continue }                            # a $( ), backticks, ${ } or $(( )) in it opens its
            if (c == "\047") { k = index(substr(s, i + 1), "\047"); if (!k) { lost(s); return } i += k + 1; continue }   # level
            if (c == "\"") { pushd(0); i++; continue }
            k = inner(s, i, c); if (k) { i = k; continue }
            if (TY[sp] == "P") { if (c == "}") sp--; i++; continue }       # its first } ends it, as bash ends it
            if (c == "$") { i++; while (i <= n && substr(s, i, 1) ~ /[A-Za-z0-9_]/) i++; continue }   # $name: a variable
            if (c ~ /[A-Za-z_]/) {                                         # a name: a variable to bash — fail-closed when it
                k = i; while (i <= n && substr(s, i, 1) ~ /[A-Za-z0-9_]/) i++   # is a watched word ($((alert …) ) runs it)
                d = substr(s, k, i - k); if (watched(d) && d != "alert_info") { nm++; MW[nm] = d }
                continue
            }
            if (c == "(") { PA[sp]++; i++; continue }
            if (c == ")") { if (PA[sp] > 0) { PA[sp]--; i++; continue } sp--; i += (substr(s, i + 1, 1) == ")") ? 2 : 1; continue }
            i++; continue
        }
        if (c == "\047") { wstart(i); WQ[sp] = 1; k = index(substr(s, i + 1), "\047"); if (!k) { lost(s); return } WT[sp] = WT[sp] substr(s, i + 1, k - 1); i += k + 1; continue }
        if (c == "\"") { wstart(i); WQ[sp] = 1; pushd(sp); i++; continue }
        if (c == "\\") { wstart(i); WQ[sp] = 1; WT[sp] = WT[sp] substr(s, i + 1, 1); i += 2; continue }
        if (c == "#" && !INW[sp]) { lost(s); return }                     # a comment
        if (c == "`") {
            if (CLO[sp] == "`") { endword(s, i); sp--; i++; continue }
            wstart(i); WX[sp] = 1; pushc("`"); i++; continue
        }
        if (c == "$") {
            d = substr(s, i + 1, 1)
            if (d == "\047") {                                             # $'…': an ANSI-C quoted part of the word
                wstart(i); WQ[sp] = 1; i += 2
                while (i <= n) { c = substr(s, i, 1); if (c == "\\") { WE[sp] = 1; WT[sp] = WT[sp] substr(s, i, 2); i += 2; continue } i++; if (c == "\047") break; WT[sp] = WT[sp] c }
                continue
            }
            if (d == "\"") { wstart(i); WQ[sp] = 1; pushd(sp); i += 2; continue }   # $"…": a locale-translated "…"
            wstart(i); WX[sp] = 1
            k = inner(s, i, c); if (k) { i = k; continue }                 # $( … ) code; ${ … } and $(( … )): their levels
            if (d ~ /[$#?!@*0-9-]/) { i += 2; continue }                   # a special parameter: $$ $# $? $! $@ $* $- $0-$9
            i++; continue
        }
        if (c ~ /[ \t]/) { endword(s, i); i++; continue }
        if (c == "<" || c == ">" || (c == "&" && substr(s, i + 1, 1) == ">")) {   # a redirection: its operator, then its target
            if (INW[sp] && !WQ[sp] && !WX[sp] && WT[sp] ~ /^[0-9]+$/) INW[sp] = 0     # "2>": the fd number, not a word
            else endword(s, i)
            if ((c == "<" || c == ">") && substr(s, i + 1, 1) == "(") { wstart(i); WX[sp] = 1; pushc(")"); i += 2; continue }   # <( … ) >( … ): code
            op = c; i++
            while (i <= n && substr(s, i, 1) ~ /[<>&|-]/) { op = op substr(s, i, 1); i++ }
            if (op ~ /&$/ && substr(s, i, 1) ~ /[0-9]/) { while (i <= n && substr(s, i, 1) ~ /[0-9]/) i++; continue }   # >&2
            if (op ~ /&-$/) continue                                        # >&- closes: no target word
            while (i <= n && substr(s, i, 1) ~ /[ \t]/) i++
            RDT[sp] = 1; continue
        }
        if (c ~ /[;&|]/) { endword(s, i); CPOS[sp] = 1; RDT[sp] = 0; i++; continue }
        if (c == "(") {
            if (INW[sp] && !WQ[sp] && substr(WT[sp], length(WT[sp]), 1) == "=") { WX[sp] = 1; pushc(")"); CPOS[sp] = 0; i++; continue }   # NAME=( … ): an array value — its words are arguments, its $( ) code
            endword(s, i); PD[sp]++; CPOS[sp] = 1; i++; continue
        }
        if (c == ")") {
            endword(s, i)
            if (PD[sp] > 0) { PD[sp]--; CPOS[sp] = 1; i++; continue }
            if (CLO[sp] == ")") { sp--; i++; continue }
            CPOS[sp] = 1; i++; continue
        }
        if ((c == "{" || c == "}") && !INW[sp]) { CPOS[sp] = 1; i++; continue }
        wstart(i); WT[sp] = WT[sp] c; i++
    }
    lost(s)                                                                # a level left open: a U row (the caller)
    while (sp > 1 && TY[sp] != "C") sp--                                   # a quote or an expansion left open: its word ends
    endword(s, n + 1)
}
FNR == 1 { if (first == "") { first = FILENAME; pass = 1 } else if (FILENAME == first) pass = 2; fn = ""; base = FILENAME; sub(/.*\//, "", base) }
/^[ \t]*#/ || /^[ \t]*$/ { next }
/^[ \t]*(function[ \t]+)?[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)/ && !/^[A-Za-z_][A-Za-z0-9_]*\(\)[ \t]*\{/ {
    if (pass == 2) printf "X\t%s:%d\ta function defined in another shape than `name() {` at column 0 (its wrapper calls would go unseen)\n", base, FNR
}
/^[A-Za-z_][A-Za-z0-9_]*\(\)[ \t]*\{/ { fn = $0; sub(/\(.*/, "", fn) }
/^\}/ { fn = "" }
{
    calls($0); at = base ":" FNR; cont = ($0 ~ /\\$/)
    for (k = 1; k <= nc; k++) {
        w = CW[k]
        scanargs($0, CP[k], CC[k])
        if (w == "alert_info") { if (pass == 2) { ninfo++; h = (na >= 1 && !open) ? heading(1) : ""; printf "N\t%s\tinfo\t%s\n", at, (h == "" ? "(no literal heading)" : h) } continue }
        if (w == "send_telegram" || w == "send_webhook") {
            if (fn in SINK) continue                                          # the transport of a sink's caller
            pos = (w == "send_webhook") ? 3 : 1; kind = (w == "send_webhook") ? "webhook" : "direct"   # send_webhook's title: its status
            if (na >= pos && AR[pos] ~ /^\$([1-9]|\{[1-9]\})$/ && fn != "") {   # a wrapper's own forward
                if (pass == 1) { WR[fn] = kind; WA[fn] = AR[pos]; gsub(/[^0-9]/, "", WA[fn]); WA[fn] += 0; printf "W\t%s\t%s\t%s\n", fn, kind, AR[pos] }
                continue
            }
            if (pass == 2) row(kind, pos, "")
            continue
        }
        if (w == "alert" || w == "alert_warn") {
            pos = (w == "alert") ? 3 : 1
            if (na >= pos && AR[pos] ~ /^\$([1-9]|\{[1-9]\})$/ && fn != "") {       # the wrapper's own forward
                if (pass == 1) { WR[fn] = w; WA[fn] = AR[pos]; gsub(/[^0-9]/, "", WA[fn]); WA[fn] += 0; printf "W\t%s\t%s\t%s\n", fn, w, AR[pos] }
                continue
            }
            if (pass == 2) row((w == "alert") ? "status" : "heading", pos, "")
            continue
        }
        if (pass == 2) row((WR[w] == "alert") ? "status" : ((WR[w] == "direct" || WR[w] == "webhook") ? WR[w] : "heading"), WA[w], w ": ")   # a wrapper's caller
    }
    if (pass == 2) {
        for (k = 1; k <= nq; k++) printf "U\t%s\tcall\tthe call word %s spelled with quotes or a backslash\n", at, QW[k]
        for (k = 1; k <= ne; k++) printf "U\t%s\tcall\ta command word holding an ANSI-C escape this reader does not decode: $'%s'\n", at, EW[k]
        for (k = 1; k <= nm; k++) if (!(MW[k] == "send_telegram" || MW[k] == "send_webhook") || !(fn in SINK)) printf "U\t%s\tcall\tthe word %s where no call was read (an argument — behind eval / command / exec / a tool — or a word this reader cannot place)\n", at, MW[k]
        if (LOST != "") printf "U\t%s\tcall\ta %s still open at the end of the line (a construct spanning lines, or a line the reader lost its place on: a call after that point would go unread)\n", at, LOST
    }
    if ($0 ~ /^[A-Za-z_][A-Za-z0-9_]*\(\)[ \t]*\{.*\}[ \t]*$/) fn = ""           # a one-line function ends on its line
}
END { printf "I\t%d\n", ninfo + 0 }
