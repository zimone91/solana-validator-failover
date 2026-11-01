#!/bin/bash
# v0.7 (AG-1.5): READINESS FACTS — the running validator's version against MIN_VALIDATOR_VERSION (G8) and the class of a LOCAL getHealth
# answer (G9). Both are NAMING functions of the [ag] block (byte-identical in the two daemons): they decide nothing in a take path — the AG
# page (AG-1.2) prints them, a startup page says once when the version is not ready, and Tier-1 / the two self-fence sites keep their
# decisions (this slice changes none) while saying what they read.
#   (1)  _semver_cmp: semver 2.0.0 precedence on a table (pre-release before release, numeric identifiers by value, numeric before
#        alphanumeric, ASCII order, build metadata ignored) — every valid pair also in the reverse order; invalid inputs return 1
#   (2)  _health_class: ok / behind N / unknown (error -32005 + numSlotsBehind null: agave's Unknown, rpc_health.rs:94-103, D0.6) /
#        unreadable (no body, not JSON, another error, a garbage, negative, fractional or quoted count, a wrong code)
#   (3)  _version_eval over a shadowed LOCAL curl: getVersion on LOCAL_RPC only, field solana-core; ok / below / unreadable / frankendancer
#        (not checked: zero reads); MIN_VALIDATOR_VERSION moved; a minimum that is no version
#   (4)  _version_startup_check: ONE page per run — below the minimum at the first determination, an unreadable version after 900 s of
#        60 s retries, never for ok / frankendancer; no read inside the 60 s cadence; no read once decided
#   (5)  MIN_VALIDATOR_VERSION: validated as semver at startup (a bad value refuses), drift-announced when LOWER than 4.4.0 (higher: silent)
#   (6)  Tier-1: an Unknown answer is NOT READY by name (same rc 1 as before); the other answers read as they always did
#   (7)  the self-fence getHealth site: Unknown names itself in the log ONCE and demotes nothing; behind 200 > 150 still demotes
#   (8)  wiring: the main loop calls _version_startup_check after the tripwire; the [ag] block is byte-identical in both daemons
#   (9)  CONTROLS (mutate()): a lexical number compare, a pre-release that orders after its release, numeric-after-alphanumeric, Unknown read
#        as behind, a count without the canonical check, quoted counts accepted, a below that reads ok, a startup page that repeats, an
#        early unreadable page, an inverted drift direction, a Tier-1 Unknown that reads ready, a self-fence log with no change guard
# RED ON THE BASE (fd4ee8c + AG-1.1/AG-1.3): none of these functions exists.
#
# harness: tests/lib/harness.sh — ok/bad+banners, paths, field, mutate, drift_out, extract_twin.
set +e
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

title_banner "Alpenglow readiness: the version minimum and the getHealth classes (v0.7 AG-1.5)"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/agr.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

cut_src() {   # cut_src <script> → a file holding the daemon up to its MAIN LOOP marker (the seam)
    local f="$WORK/seam.$(printf '%s' "$1" | cksum | cut -d' ' -f1).$$.$RANDOM"
    sed -n '1,/MAIN LOOP/p' "$1" > "$f"; printf '%s' "$f"
}
role_of() { basename "$1" | sed 's/solana-\(.*\)-failover.sh/\1/'; }

# ── (1) semver precedence ─────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (1) _semver_cmp: semver 2.0.0 precedence (a|b|expected), both orders ───"
SV_VECTORS='4.4.0|4.4.0|0
4.4.1|4.4.0|1
4.5.0|4.4.9|1
5.0.0|4.99.99|1
4.10.0|4.9.9|1
4.9.9|4.10.0|-1
999999999.0.0|999999998.9.9|1
4.4.0-rc.1|4.4.0|-1
4.4.0-rc.1|4.4.0-rc.2|-1
4.4.0-rc.2|4.4.0-rc.10|-1
4.4.0-rc.1|4.3.9|1
1.0.0-alpha|1.0.0-alpha.1|-1
1.0.0-alpha.1|1.0.0-alpha.beta|-1
1.0.0-alpha.beta|1.0.0-beta|-1
1.0.0-beta|1.0.0-beta.2|-1
1.0.0-beta.2|1.0.0-beta.11|-1
1.0.0-beta.11|1.0.0-rc.1|-1
1.0.0-rc.1|1.0.0|-1
1.0.0-1|1.0.0-a|-1
1.0.0-Z|1.0.0-a|-1
1.0.0-a|1.0.0-b|-1
1.0.0-alpha-1|1.0.0-alpha-2|-1
4.4.0+build5|4.4.0|0
4.4.0+a|4.4.0+b|0
4.4.0-rc.1+x|4.4.0-rc.1|0
4.4|4.4.0|invalid
v4.4.0|4.4.0|invalid
4.4.0.1|4.4.0|invalid
|4.4.0|invalid
4.4.0-|4.4.0|invalid
4.4.0-a..b|4.4.0|invalid
4.4.0|abc|invalid
4.4.0||invalid
4.4.0 |4.4.0|invalid
4.4.0 (src:abcdef01)|4.4.0|invalid'
sv_run() {   # sv_run <script> → the mismatching lines, then "COUNT n"
    local cs; cs=$(cut_src "$1")
    (
        set +e
        # shellcheck disable=SC1090
        source "$cs" 2>/dev/null
        n=0
        while IFS='|' read -r a b want; do
            [[ -z "$a$b$want" ]] && continue
            got=$(_semver_cmp "$a" "$b" 2>/dev/null); rc=$?
            [[ $rc -ne 0 ]] && got=invalid
            [[ "$got" == "$want" ]] || echo "MISMATCH cmp('$a','$b') = '$got', want '$want'"
            if [[ "$want" != "invalid" ]]; then
                rev=$(_semver_cmp "$b" "$a" 2>/dev/null); exp=0
                [[ "$want" == "1" ]] && exp=-1; [[ "$want" == "-1" ]] && exp=1
                [[ "$rev" == "$exp" ]] || echo "ASYMMETRY cmp('$b','$a') = '$rev', want '$exp'"
            fi
            n=$((n + 1))
        done <<< "$SV_VECTORS"
        echo "COUNT $n"
    )
}
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(role_of "$scr"); out=$(sv_run "$scr")
    [[ "$out" == "COUNT 35" ]] \
        && ok "(1a:$n) all 35 vectors read as expected, and every valid pair reversed gives the opposite (the semver spec's own chain alpha < alpha.1 < alpha.beta < beta < beta.2 < beta.11 < rc.1 < release included)" \
        || bad "(1a:$n) semver table: $(printf '%s' "$out" | head -4 | tr '\n' ';')"
done

# ── (2) the getHealth classes ─────────────────────────────────────────────────────────────────────
echo ""; echo "─── (2) _health_class: ok / behind N / unknown / unreadable (name|expected|body) ───"
HC_CASES='ok|ok|{"jsonrpc":"2.0","result":"ok","id":1}
unknown|unknown|{"jsonrpc":"2.0","error":{"code":-32005,"message":"Node is unhealthy","data":{"numSlotsBehind":null}},"id":1}
behind200|behind 200|{"jsonrpc":"2.0","error":{"code":-32005,"message":"Node is behind by 200 slots","data":{"numSlotsBehind":200}},"id":1}
behind0|behind 0|{"jsonrpc":"2.0","error":{"code":-32005,"message":"Node is behind by 0 slots","data":{"numSlotsBehind":0}},"id":1}
garbage-string|unreadable|{"jsonrpc":"2.0","error":{"code":-32005,"message":"m","data":{"numSlotsBehind":"abc"}},"id":1}
quoted-count|unreadable|{"jsonrpc":"2.0","error":{"code":-32005,"message":"m","data":{"numSlotsBehind":"200"}},"id":1}
leading-zeros|unreadable|{"jsonrpc":"2.0","error":{"code":-32005,"message":"m","data":{"numSlotsBehind":"0000300"}},"id":1}
negative|unreadable|{"jsonrpc":"2.0","error":{"code":-32005,"message":"m","data":{"numSlotsBehind":-5}},"id":1}
fractional|unreadable|{"jsonrpc":"2.0","error":{"code":-32005,"message":"m","data":{"numSlotsBehind":200.5}},"id":1}
boolean|unreadable|{"jsonrpc":"2.0","error":{"code":-32005,"message":"m","data":{"numSlotsBehind":true}},"id":1}
array|unreadable|{"jsonrpc":"2.0","error":{"code":-32005,"message":"m","data":{"numSlotsBehind":[200]}},"id":1}
wrong-code|unreadable|{"jsonrpc":"2.0","error":{"code":-32000,"message":"m","data":{"numSlotsBehind":null}},"id":1}
code-as-string|unreadable|{"jsonrpc":"2.0","error":{"code":"-32005","message":"m","data":{"numSlotsBehind":null}},"id":1}
no-data|unreadable|{"jsonrpc":"2.0","error":{"code":-32005,"message":"Node is unhealthy"},"id":1}
data-not-object|unreadable|{"jsonrpc":"2.0","error":{"code":-32005,"message":"m","data":5},"id":1}
no-field|unreadable|{"jsonrpc":"2.0","error":{"code":-32005,"message":"m","data":{}},"id":1}
other-result|unreadable|{"jsonrpc":"2.0","result":"behind","id":1}
no-result|unreadable|{"jsonrpc":"2.0","id":1}
not-json|unreadable|<html>502 Bad Gateway</html>
array-body|unreadable|[]
number-body|unreadable|5
empty|unreadable|'
hc_run() {   # hc_run <script> → the mismatching cases, then "COUNT n"
    local cs; cs=$(cut_src "$1")
    (
        set +e
        # shellcheck disable=SC1090
        source "$cs" 2>/dev/null
        n=0
        while IFS='|' read -r name want body; do
            [[ -z "$name$want" ]] && continue
            got=$(_health_class "$body"); rc=$?
            [[ "$got" == "$want" && $rc -eq 0 ]] || echo "MISMATCH $name: '$got' (rc $rc), want '$want'"
            n=$((n + 1))
        done <<< "$HC_CASES"
        got=$(_health_class); [[ "$got" == "unreadable" ]] || echo "MISMATCH no-argument: '$got'"
        echo "COUNT $n"
    )
}
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(role_of "$scr"); out=$(hc_run "$scr")
    [[ "$out" == "COUNT 22" ]] \
        && ok "(2a:$n) 22 getHealth answers classified as the D0.6 shapes say: Unknown (error -32005 + numSlotsBehind null) is named by that, a number only as a canonical JSON number, anything else unreadable" \
        || bad "(2a:$n) health table: $(printf '%s' "$out" | head -4 | tr '\n' ';')"
done

# ── (3) the version read ──────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (3) _version_eval over a shadowed LOCAL curl: getVersion, solana-core ───"
VER_BODY() { printf '{"jsonrpc":"2.0","result":{"feature-set":3140108883,"solana-core":"%s"},"id":1}' "$1"; }
ve_run() {   # ve_run <script> <body|RC7|EMPTY> [VAR=val …] → state=…|text=…|calls=…|req=…
    local script="$1" body="$2" cs kv; shift 2
    cs=$(cut_src "$script")
    (
        set +e
        # shellcheck disable=SC1090
        source "$cs" 2>/dev/null
        LOCAL_RPC="http://mock-local"; TIER2_RPC="http://mock-t2"; TIER3_RPC="http://mock-t3"; VALIDATOR_TYPE=agave; MIN_VALIDATOR_VERSION=4.4.0
        for kv in "$@"; do eval "$kv"; done
        CF=$(mktemp); trap 'rm -f "$CF"' EXIT
        _watchdog_pet() { :; }; log_info() { :; }; log_warn() { :; }
        curl() {
            local url="" data=""
            while [[ $# -gt 0 ]]; do case "$1" in -d) data="$2"; shift 2; continue ;; http*) url="$1" ;; esac; shift; done
            echo "$url $data" >> "$CF"
            case "$body" in RC7) return 7 ;; EMPTY) return 0 ;; esac
            printf '%s' "$body"; return 0
        }
        _version_eval
        printf 'state=%s|text=%s|calls=%s|req=%s\n' "$_ver_state" "$_ver_text" "$(wc -l < "$CF" | tr -d ' ')" "$(head -1 "$CF")"
    )
}
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(role_of "$scr")
    out=$(ve_run "$scr" "$(VER_BODY 4.4.0)")
    [[ "$(field "$out" state)" == "ok" && "$(field "$out" text)" == "ok (version 4.4.0, minimum 4.4.0)" && "$(field "$out" calls)" == "1" \
       && "$(field "$out" req)" == 'http://mock-local {"jsonrpc":"2.0","id":1,"method":"getVersion"}' ]] \
        && ok "(3a:$n) 4.4.0 (agave and jito both answer it) → ok; ONE read, getVersion on LOCAL_RPC only (no T2/T3, no executable)" \
        || bad "(3a:$n) 4.4.0 misread ($out)"
    out=$(ve_run "$scr" "$(VER_BODY 4.3.2)")
    [[ "$(field "$out" state)" == "below" && "$(field "$out" text)" == "not ready (version 4.3.2 is below the minimum 4.4.0)" ]] \
        && ok "(3b:$n) 4.3.2 → below: 'not ready (version 4.3.2 is below the minimum 4.4.0)'" || bad "(3b:$n) 4.3.2 misread ($out)"
    out=$(ve_run "$scr" "$(VER_BODY 4.4.0-rc.1)")
    [[ "$(field "$out" state)" == "below" ]] && ok "(3c:$n) 4.4.0-rc.1 → below (a pre-release orders before its release: conservative)" || bad "(3c:$n) rc misread ($out)"
    for v in 4.4.1 5.0.0 4.10.0; do
        out=$(ve_run "$scr" "$(VER_BODY "$v")"); [[ "$(field "$out" state)" == "ok" ]] || bad "(3d:$n) $v is not ok ($out)"
    done
    ok "(3d:$n) 4.4.1, 5.0.0 and 4.10.0 are ok (numeric, not lexical)"
    out=$(ve_run "$scr" "$(VER_BODY 4.4.0)" 'MIN_VALIDATOR_VERSION=4.5.0')
    [[ "$(field "$out" state)" == "below" && "$(field "$out" text)" == *"minimum 4.5.0"* ]] \
        && ok "(3e:$n) a raised minimum (4.5.0) moves the verdict: 4.4.0 is below" || bad "(3e:$n) raised minimum ignored ($out)"
    for fx in "src-string:$(VER_BODY '4.4.0 (src:abcdef01; feat:1)')" "number:{\"jsonrpc\":\"2.0\",\"result\":{\"solana-core\":4},\"id\":1}" \
              "no-field:{\"jsonrpc\":\"2.0\",\"result\":{\"feature-set\":1},\"id\":1}" "rpc-error:{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32601,\"message\":\"Method not found\"},\"id\":1}" \
              "not-json:<html>502</html>" "empty:EMPTY" "transport:RC7"; do
        out=$(ve_run "$scr" "${fx#*:}")
        [[ "$(field "$out" state)" == "unreadable" && "$(field "$out" text)" == "not ready (the version is unreadable:"* ]] \
            || bad "(3f:$n:${fx%%:*}) not unreadable ($out)"
    done
    ok "(3f:$n) a non-version string, a number, a missing field, a JSON-RPC error, non-JSON, an empty answer and a transport failure all read unreadable — 'not ready (the version is unreadable: …)'"
    out=$(ve_run "$scr" "$(VER_BODY 4.4.0)" 'MIN_VALIDATOR_VERSION=latest')
    [[ "$(field "$out" state)" == "unreadable" && "$(field "$out" text)" == *"the minimum 'latest' is not a semantic version"* ]] \
        && ok "(3g:$n) a minimum that is no version reads unreadable, never ok" || bad "(3g:$n) bad minimum misread ($out)"
    out=$(ve_run "$scr" "$(VER_BODY 4.3.2)" 'VALIDATOR_TYPE=frankendancer')
    [[ "$(field "$out" state)" == "skip" && "$(field "$out" text)" == "not checked (frankendancer)" && "$(field "$out" calls)" == "0" ]] \
        && ok "(3h:$n) frankendancer → 'not checked (frankendancer)', ZERO reads (a named limit)" || bad "(3h:$n) frankendancer misread ($out)"
done

# ── (4) the startup page ──────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (4) _version_startup_check: one page per run, on the cadence ───"
vs_run() {   # vs_run <script> [VAR=val …] -- <t>:<body> … → pages=…|curls=…|done=…|ptext=…|logs=…
    local script="$1" cs kv; shift
    cs=$(cut_src "$script")
    local -a ov=() seq=()
    while [[ $# -gt 0 && "$1" != "--" ]]; do ov+=("$1"); shift; done
    [[ "${1:-}" == "--" ]] && shift
    seq=("$@")
    (
        set +e
        # shellcheck disable=SC1090
        source "$cs" 2>/dev/null
        LOCAL_RPC="http://mock-local"; VALIDATOR_TYPE=agave; MIN_VALIDATOR_VERSION=4.4.0
        for kv in "${ov[@]}"; do eval "$kv"; done
        PG=0; PT=""; LG=""; CF=$(mktemp); trap 'rm -f "$CF"' EXIT
        _watchdog_pet() { :; }; log_info() { LG="$LG ‖ I:$*"; }; log_warn() { LG="$LG ‖ W:$*"; }
        alert_warn() { PG=$((PG + 1)); [[ -z "$PT" ]] && PT="$1"; return 0; }
        _NOW=0; mono_now() { echo "$_NOW"; }
        curl() { echo C >> "$CF"; case "$_BODY" in RC7) return 7 ;; EMPTY) return 0 ;; esac; printf '%s' "$_BODY"; return 0; }
        for e in "${seq[@]}"; do _NOW="${e%%:*}"; _BODY="${e#*:}"; _version_startup_check; done
        printf 'pages=%s|curls=%s|done=%s|ptext=%s|logs=%s\n' "$PG" "$(wc -l < "$CF" | tr -d ' ')" "$_ver_done" "$PT" "$LG"
    )
}
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(role_of "$scr"); OKB=$(VER_BODY 4.4.0); LOWB=$(VER_BODY 4.3.2)
    out=$(vs_run "$scr" -- "100:$OKB" "200:$OKB" "300:$OKB")
    [[ "$(field "$out" pages)" == "0" && "$(field "$out" curls)" == "1" && "$(field "$out" done)" == "1" && "$(field "$out" logs)" == *"I:[version] ok (version 4.4.0, minimum 4.4.0)"* ]] \
        && ok "(4a:$n) ok at the first read: a log line, ZERO pages, and the later cycles read nothing (decided)" || bad "(4a:$n) ok misread ($out)"
    out=$(vs_run "$scr" -- "100:$LOWB" "200:$LOWB" "300:$LOWB")
    [[ "$(field "$out" pages)" == "1" && "$(field "$out" curls)" == "1" && "$(field "$out" ptext)" == "⚠️ VALIDATOR VERSION NOT READY: not ready (version 4.3.2 is below the minimum 4.4.0)."* ]] \
        && ok "(4b:$n) below the minimum: ONE page at the first determination (heading '⚠️ VALIDATOR VERSION NOT READY:', both versions named), never again" || bad "(4b:$n) below misread ($out)"
    out=$(vs_run "$scr" -- "100:$OKB" "110:$OKB" "119:$OKB")
    [[ "$(field "$out" curls)" == "1" ]] && ok "(4c:$n) the cadence: three calls inside 60 s make one read" || bad "(4c:$n) cadence ($out)"
    seq=(); t=100; while [[ $t -le 1000 ]]; do seq+=("$t:RC7"); t=$((t + 60)); done
    out=$(vs_run "$scr" -- "${seq[@]}")
    [[ "$(field "$out" pages)" == "1" && "$(field "$out" curls)" == "16" && "$(field "$out" ptext)" == *"VERSION NOT READY"*"unreadable"* && "$(field "$out" ptext)" == *"900s"* ]] \
        && ok "(4d:$n) an unreadable version: 15 minutes of 60 s retries (16 reads), then ONE page naming the 900 s — not a page at startup while LOCAL_RPC may still be coming up" || bad "(4d:$n) unreadable misread ($out)"
    seq=(); t=100; while [[ $t -le 940 ]]; do seq+=("$t:RC7"); t=$((t + 60)); done
    out=$(vs_run "$scr" -- "${seq[@]}")
    [[ "$(field "$out" pages)" == "0" && "$(field "$out" done)" == "0" ]] \
        && ok "(4e:$n) unreadable for 840 s (the last read at 940 = 840 s after the first): still no page, still retrying" || bad "(4e:$n) early unreadable page ($out)"
    out=$(vs_run "$scr" -- "100:RC7" "160:RC7" "220:$OKB" "280:$OKB")
    [[ "$(field "$out" pages)" == "0" && "$(field "$out" done)" == "1" && "$(field "$out" curls)" == "3" ]] \
        && ok "(4f:$n) unreadable while LOCAL_RPC starts, then ok: no page at all" || bad "(4f:$n) recovery misread ($out)"
    out=$(vs_run "$scr" 'VALIDATOR_TYPE=frankendancer' -- "100:$LOWB" "200:$LOWB")
    [[ "$(field "$out" pages)" == "0" && "$(field "$out" curls)" == "0" && "$(field "$out" done)" == "1" && "$(field "$out" logs)" == *"not checked (frankendancer)"* ]] \
        && ok "(4g:$n) frankendancer: a log line, zero reads, zero pages" || bad "(4g:$n) frankendancer misread ($out)"
done

# ── (5) the knob: validated, drift-announced ──────────────────────────────────────────────────────
echo ""; echo "─── (5) MIN_VALIDATOR_VERSION: refused when it is no version; announced when LOWER than the default ───"
rc_of() {   # rc_of <script> VAR=val… → validate_numeric_config's exit code under the overrides (a bad knob exits 1 inside the inner shell)
    local script="$1" cs kv; shift
    cs=$(cut_src "$script")
    (
        # shellcheck disable=SC1090
        source "$cs" 2>/dev/null
        log_info() { :; }; log_warn() { :; }; log_error() { :; }
        for kv in "$@"; do eval "$kv"; done
        ( validate_numeric_config ) >/dev/null 2>&1
        echo $?
    )
}
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(role_of "$scr")
    [[ "$(rc_of "$scr")" == "0" && "$(rc_of "$scr" 'MIN_VALIDATOR_VERSION=4.5.0-rc.1')" == "0" && "$(rc_of "$scr" 'MIN_VALIDATOR_VERSION=4.4.0+build')" == "0" ]] \
        && ok "(5a:$n) the default config passes; 4.5.0-rc.1 and 4.4.0+build are accepted versions" || bad "(5a:$n) a valid minimum was refused"
    bad_rc=""
    for v in abc 4.4 v4.4.0 latest ""; do [[ "$(rc_of "$scr" "MIN_VALIDATOR_VERSION='$v'")" == "1" ]] || bad_rc="$bad_rc '$v'"; done
    [[ -z "$bad_rc" ]] && ok "(5b:$n) 'abc', '4.4', 'v4.4.0', 'latest' and '' are refused at startup (exit 1)" || bad "(5b:$n) accepted:$bad_rc"
    d=$(drift_out "$scr" 'MIN_VALIDATOR_VERSION=4.3.0')
    [[ "$(printf '%s\n' "$d" | grep -c '\[config-drift\] MIN_VALIDATOR_VERSION=4.3.0 is laxer than this version.s default 4.4.0')" == "1" && "$d" == *"align: set MIN_VALIDATOR_VERSION=4.4.0"* ]] \
        && ok "(5c:$n) a LOWER minimum (4.3.0) is announced once: laxer than the default 4.4.0, with the fix" || bad "(5c:$n) lower minimum not announced ($d)"
    d=$(drift_out "$scr" 'MIN_VALIDATOR_VERSION=4.4.0-rc.1')
    [[ "$(printf '%s\n' "$d" | grep -c 'MIN_VALIDATOR_VERSION')" == "1" ]] \
        && ok "(5d:$n) 4.4.0-rc.1 is lower than 4.4.0 and announced (a release candidate would pass as ready)" || bad "(5d:$n) rc minimum not announced ($d)"
    d1=$(drift_out "$scr" 'MIN_VALIDATOR_VERSION=4.5.0'); d2=$(drift_out "$scr"); d3=$(drift_out "$scr" 'MIN_VALIDATOR_VERSION=abc')
    [[ -z "$(printf '%s' "$d1$d2$d3" | grep MIN_VALIDATOR_VERSION)" ]] \
        && ok "(5e:$n) a higher minimum, the default and a value that is no version (the validator's to refuse) are silent" || bad "(5e:$n) drift noise ($d1|$d2|$d3)"
done

# ── (6) Tier-1 ────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (6) Tier-1 (standby): an Unknown getHealth is NOT READY by name; the other answers read as ever ───"
t1_run() {   # t1_run <script> <getHealth body> → rc=…|log=…
    local script="$1" body="$2" cs
    cs=$(cut_src "$script")
    (
        set +e
        # shellcheck disable=SC1090
        source "$cs" 2>/dev/null
        LOCAL_RPC="http://mock-local"; STAT_TIER1_HEALTH=0; LG=""
        _watchdog_pet() { :; }; log_info() { LG="$LG ‖ I:$*"; }; log_warn() { LG="$LG ‖ W:$*"; }
        curl() { local d=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-d" ]] && { d="$2"; shift 2; continue; }; shift; done
                 case "$d" in *getHealth*) printf '%s' "$body" ;; *getSlot*) printf '{"jsonrpc":"2.0","result":777,"id":1}' ;; *) return 7 ;; esac; return 0; }
        tier1_check_local_health; rc=$?
        printf 'rc=%s|log=%s\n' "$rc" "$LG"
    )
}
T1_OK='{"jsonrpc":"2.0","result":"ok","id":1}'
T1_UNK='{"jsonrpc":"2.0","error":{"code":-32005,"message":"Node is unhealthy","data":{"numSlotsBehind":null}},"id":1}'
T1_B200='{"jsonrpc":"2.0","error":{"code":-32005,"message":"Node is behind by 200 slots","data":{"numSlotsBehind":200}},"id":1}'
out=$(t1_run "$STANDBY" "$T1_UNK")
[[ "$(field "$out" rc)" == "1" && "$(field "$out" log)" == *"W:[TIER1] getHealth answers UNKNOWN (Alpenglow: the node has seen no finalized slot yet) — not ready to take over"* ]] \
    && ok "(6a) Unknown → rc 1 (not ready, as before) and the log says UNKNOWN by name" || bad "(6a) Tier-1 Unknown misread ($out)"
out=$(t1_run "$STANDBY" "$T1_OK")
[[ "$(field "$out" rc)" == "0" && "$(field "$out" log)" == *"I:[TIER1] Health OK — slot 777"* ]] && ok "(6b) ok → rc 0, 'Health OK — slot 777' (unchanged)" || bad "(6b) Tier-1 ok misread ($out)"
out=$(t1_run "$STANDBY" "$T1_B200")
[[ "$(field "$out" rc)" == "1" && "$(field "$out" log)" == *"W:[TIER1] 200 slots behind"* && "$(field "$out" log)" != *"UNKNOWN"* ]] \
    && ok "(6c) behind 200 → rc 1 with the unchanged '200 slots behind' text (not UNKNOWN)" || bad "(6c) Tier-1 behind misread ($out)"
out=$(t1_run "$STANDBY" '{"jsonrpc":"2.0","error":{"code":-32005,"message":"Node is unhealthy"},"id":1}')
[[ "$(field "$out" rc)" == "1" && "$(field "$out" log)" == *"W:[TIER1] Unhealthy: Node is unhealthy — not ready"* ]] \
    && ok "(6d) an unhealthy answer with no numSlotsBehind field keeps its old 'Unhealthy: …' text (the classifier calls it unreadable, not Unknown)" || bad "(6d) Tier-1 legacy shape misread ($out)"

# ── (7) the self-fence getHealth site (both daemons): names Unknown once, demotes nothing ──────────
echo ""; echo "─── (7) the LOCAL getHealth site of the holder's self-fence: Unknown is named once and decides nothing ───"
sf_run() {   # sf_run <script> <health body…> → per call: rc,fenced,loglines — one cycle per body, state kept across them
    local script="$1" cs; shift
    cs=$(cut_src "$script")
    (
        set +e
        # shellcheck disable=SC1090
        source "$cs" 2>/dev/null
        LOCAL_RPC="http://mock-local"; STAKED_PUBKEY="StakedPubkey111111111111111111111111111111"; UNSTAKED_PUBKEY="UnstakedPubkey1111111111111111111111111111"
        VOTE_PUBKEY="VotePubkey1111111111111111111111111111111"
        SELF_FENCE_ISOLATION_SECS=30; SELF_FENCE_MAX_BEHIND=150; SELF_FENCE_NOANSWER_SECS=30; SELF_FENCE_VOTE_LAG_SLOTS=0; SELF_FENCE_VOTE_LAG_SECS=0
        TG_ENABLED=false; DRY_RUN=false; CURRENT_IDENTITY="$STAKED_PUBKEY"
        _watchdog_pet() { :; }; send_telegram() { return 0; }; send_webhook() { :; }; alert() { :; }; alert_warn() { :; }; save_state() { :; }
        mono_now() { date +%s; }
        LF="$WORK/sf.log.$$.$RANDOM"; : > "$LF"
        log_info() { echo "I:$*" >> "$LF"; }; log_warn() { echo "W:$*" >> "$LF"; }; log_error() { echo "E:$*" >> "$LF"; }
        FC=0; switch_to_unstaked() { FC=$((FC + 1)); CURRENT_IDENTITY="$UNSTAKED_PUBKEY"; return 0; }
        _selffence_demote() { FC=$((FC + 1)); CURRENT_IDENTITY="$UNSTAKED_PUBKEY"; return 0; }
        _SLOT=1000
        curl() { local d=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-d" ]] && { d="$2"; shift 2; continue; }; shift; done
                 case "$d" in *getSlot*) printf '{"jsonrpc":"2.0","result":%s,"id":1}' "$_SLOT" ;; *getHealth*) printf '%s' "$_HB" ;; *) return 7 ;; esac; return 0; }
        _selffence_reset; _last_confirmed_slot=1000; _last_confirmed_advance_ts=$(date +%s)
        out=""
        for _HB in "$@"; do
            _SLOT=$((_SLOT + 10)); : > "$LF"; CURRENT_IDENTITY="$STAKED_PUBKEY"; FC=0
            check_self_fence_isolation; rc=$?
            out="$out;rc=$rc,fenced=$FC,unknown=$(grep -c 'now reads UNKNOWN' "$LF"),reads=$(grep -c 'LOCAL getHealth now reads' "$LF")"
        done
        echo "$out"
    )
}
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(role_of "$scr")
    out=$(sf_run "$scr" "$T1_UNK" "$T1_UNK" "$T1_OK" "$T1_UNK")
    [[ "$out" == ";rc=1,fenced=0,unknown=1,reads=1;rc=1,fenced=0,unknown=0,reads=0;rc=1,fenced=0,unknown=0,reads=1;rc=1,fenced=0,unknown=1,reads=1" ]] \
        && ok "(7a:$n) Unknown, Unknown, ok, Unknown: NO demote on any (as ever); 'now reads UNKNOWN' is logged on the first and again only after a change (ok in between), never on the repeat" \
        || bad "(7a:$n) self-fence Unknown cycle: $out"
    out=$(sf_run "$scr" "$T1_B200")
    [[ "$out" == ";rc=0,fenced=1,unknown=0,reads=1" ]] \
        && ok "(7b:$n) behind 200 > SELF_FENCE_MAX_BEHIND 150 still demotes (the decision is the old one; the class is named in passing)" || bad "(7b:$n) behind-200 cycle: $out"
done

# ── (8) wiring ────────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (8) wiring: the main loop and the shared block ───"
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(role_of "$scr")
    loop=$(sed -n '/MAIN LOOP/,$p' "$scr")
    a=$(printf '%s\n' "$loop" | grep -n '^    _alpenglow_gate_check ' | head -1 | cut -d: -f1); b=$(printf '%s\n' "$loop" | grep -n '^    _version_startup_check ' | head -1 | cut -d: -f1)
    [[ -n "$a" && -n "$b" && $b -eq $((a + 1)) ]] \
        && ok "(8a:$n) the main loop calls _version_startup_check right after the tripwire, at the top (never inside a take path)" || bad "(8a:$n) wiring: tripwire at $a, version check at $b"
    [[ "$(printf '%s\n' "$loop" | grep -c '_version_startup_check')" == "1" ]] \
        && ok "(8b:$n) after the marker _version_startup_check occurs exactly once: the call at the top of the loop (not in any take path)" || bad "(8b:$n) unexpected occurrences of _version_startup_check after the marker"
done
if extract_twin '^# ── \[ag\] shared block' '^# ── \[ag\] end shared block'; then
    [[ "$TWIN_P" == "$TWIN_S" ]] \
        && ok "(8c) the [ag] block — _ag_mode, the vote-history readers, the semver and version functions, the health classifier — is byte-identical in both daemons ($(printf '%s\n' "$TWIN_P" | wc -l | tr -d ' ') lines)" \
        || bad "(8c) the [ag] block DIVERGED between the daemons"
fi

# ── (9) CONTROLS ──────────────────────────────────────────────────────────────────────────────────
echo ""; echo "─── (9) CONTROLS: every mutant must turn its case red ───"
SV_ONE=""; ctl_sv() {   # ctl_sv <label> <sed expr> — the table must now report a mismatch on each daemon
    local label="$1" expr="$2" scr n m out
    for scr in "$STANDBY" "$PRIMARY"; do
        n=$(role_of "$scr"); m="$WORK/c-$label-$n.sh"
        if mutate "$scr" "$expr" "$m"; then
            out=$(sv_run "$m")
            [[ "$out" != "COUNT 35" ]] && ok "(9:$label:$n) CONTROL: with the mutant the semver table reports $(printf '%s' "$out" | grep -c -E 'MISMATCH|ASYMMETRY') mismatch line(s)" || bad "(9:$label:$n) the semver control did not bite"
        fi
    done
}
ctl_sv lexical 's/if \[\[ \${#_a} -ne \${#_b} \]\]; then/if false; then/'
ctl_sv prerelease-after 's/\[\[ -z "\$_ar" \]\] && { echo 1; return 0; }/[[ -z "$_ar" ]] \&\& { echo -1; return 0; }/'
ctl_sv numeric-after 's/\[\[ "\$_x" =~ \^\[0-9\]+\$ \]\] && { echo -1; return 0; }/[[ "$_x" =~ ^[0-9]+$ ]] \&\& { echo 1; return 0; }/'
ctl_sv no-shorter-first 's/\[\[ \$_i -ge \${#_pa\[@\]} \]\] && { echo -1; return 0; }/[[ $_i -ge ${#_pa[@]} ]] \&\& { echo 1; return 0; }/'
ctl_hc() {   # ctl_hc <label> <sed expr>
    local label="$1" expr="$2" scr n m out
    for scr in "$STANDBY" "$PRIMARY"; do
        n=$(role_of "$scr"); m="$WORK/c-$label-$n.sh"
        if mutate "$scr" "$expr" "$m"; then
            out=$(hc_run "$m")
            [[ "$out" != "COUNT 22" ]] && ok "(9:$label:$n) CONTROL: with the mutant the health table reports a mismatch ($(printf '%s' "$out" | head -1 | cut -c1-90))" || bad "(9:$label:$n) the health control did not bite"
        fi
    done
}
ctl_hc unknown-as-behind 's/if \. == null then "unknown"/if . == null then "behind 0"/'
ctl_hc no-canonical-check 's/if _canon_uint "\$_n"; then printf .behind %s. "\$_n"; else printf .unreadable.; fi/printf "behind %s" "$_n"/'
ctl_hc quoted-count 's/elif type == "number" then "behind " + tostring/elif type == "number" or type == "string" then "behind " + tostring/'
ctl_hc wrong-code 's/\.error\.code == -32005 and/.error.code != 0 and/'
ctl_ve() {   # ctl_ve <label> <sed expr> <body> <field> <expected on the real script>
    local label="$1" expr="$2" body="$3" f="$4" want="$5" scr n m out
    for scr in "$STANDBY" "$PRIMARY"; do
        n=$(role_of "$scr"); m="$WORK/c-$label-$n.sh"
        if mutate "$scr" "$expr" "$m"; then
            out=$(ve_run "$m" "$body")
            [[ "$(field "$out" "$f")" != "$want" ]] && ok "(9:$label:$n) CONTROL: the mutant reads '$(field "$out" "$f" | cut -c1-60)' where the real function reads '$want'" || bad "(9:$label:$n) the version control did not bite ($out)"
        fi
    done
}
ctl_ve below-reads-ok 's/        -1)  _ver_state="below"/        1)  _ver_state="below"/' "$(VER_BODY 4.3.2)" state below
ctl_ve rc-reads-ok 's/\[\[ -z "\$_sv_pre" \]\] && { echo -1; return 0; }/[[ -z "$_sv_pre" ]] \&\& { echo 1; return 0; }/' "$(VER_BODY 4.4.0-rc.1)" state below
ctl_vs() {   # ctl_vs <label> <record field> <sed expr> <vs_run args…> — the mutant's record must differ from the real one in that field
    local label="$1" f="$2" expr="$3" scr n m real mut; shift 3
    for scr in "$STANDBY" "$PRIMARY"; do
        n=$(role_of "$scr"); m="$WORK/c-$label-$n.sh"
        if mutate "$scr" "$expr" "$m"; then
            real=$(vs_run "$scr" "$@"); mut=$(vs_run "$m" "$@")
            [[ "$(field "$real" "$f")" != "$(field "$mut" "$f")" ]] && ok "(9:$label:$n) CONTROL: $f $(field "$real" "$f") → $(field "$mut" "$f") with the mutant" || bad "(9:$label:$n) the startup control did not bite (real: $real :: mutant: $mut)"
        fi
    done
}
LOWB=$(VER_BODY 4.3.2)
ctl_vs page-repeats pages 's/        below)   _ver_done=1;/        below)   _ver_done=0;/' -- "100:$LOWB" "200:$LOWB" "300:$LOWB"
seq=(); t=100; while [[ $t -le 1000 ]]; do seq+=("$t:RC7"); t=$((t + 60)); done
ctl_vs unreadable-early pages 's/if \[\[ \$(( _now - _ver_first )) -ge 900 \]\]; then/if [[ $(( _now - _ver_first )) -ge 90 ]]; then/' -- "${seq[@]:0:8}"
ctl_vs no-cadence curls 's/\[\[ \${_ver_last:-0} -gt 0 && \$(( _now - _ver_last )) -lt 60 \]\] && return 0/:/' -- "100:RC7" "110:RC7" "119:RC7"
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(role_of "$scr"); m="$WORK/c-drift-$n.sh"
    if mutate "$scr" 's/\[\[ "\$(_semver_cmp "\$val" "\$def" 2>\/dev\/null)" == "-1" \]\] && lax=1/[[ "$(_semver_cmp "$val" "$def" 2>\/dev\/null)" == "1" ]] \&\& lax=1/' "$m"; then
        d1=$(drift_out "$m" 'MIN_VALIDATOR_VERSION=4.3.0'); d2=$(drift_out "$m" 'MIN_VALIDATOR_VERSION=4.5.0')
        [[ -z "$(printf '%s' "$d1" | grep MIN_VALIDATOR_VERSION)" && -n "$(printf '%s' "$d2" | grep MIN_VALIDATOR_VERSION)" ]] \
            && ok "(9:drift-inverted:$n) CONTROL: an inverted direction is silent on 4.3.0 and noisy on 4.5.0 (cases 5c/5e bite)" || bad "(9:drift-inverted:$n) the drift control did not bite ($d1|$d2)"
    fi
done
m="$WORK/c-t1.sh"
if mutate "$STANDBY" 's/        log_warn "\[TIER1\] getHealth answers UNKNOWN (Alpenglow: the node has seen no finalized slot yet) — not ready to take over"/&; return 0/' "$m"; then
    out=$(t1_run "$m" "$T1_UNK")
    [[ "$(field "$out" rc)" == "0" ]] && ok "(9:tier1-unknown-ready) CONTROL: a Tier-1 whose Unknown branch returned 0 would read READY (case 6a bites)" || bad "(9:tier1-unknown-ready) the Tier-1 control did not bite ($out)"
fi
for scr in "$STANDBY" "$PRIMARY"; do
    n=$(role_of "$scr"); m="$WORK/c-sfguard-$n.sh"
    if mutate "$scr" 's/            if \[\[ "\$_sf_hc" != "\${_health_class_seen:-}" \]\]; then/            if true; then/' "$m"; then
        out=$(sf_run "$m" "$T1_UNK" "$T1_UNK")
        [[ "$out" == *";rc=1,fenced=0,unknown=1,reads=1;rc=1,fenced=0,unknown=1,reads=1" ]] \
            && ok "(9:sf-guard:$n) CONTROL: without the change guard the repeat is logged again (case 7a bites)" || bad "(9:sf-guard:$n) the self-fence log control did not bite ($out)"
    fi
done

results_banner
