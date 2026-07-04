#!/bin/bash
# v0.6.9 (M5): collision detector — DETECTION-ONLY. Once two nodes hold staked, nothing else can see
# it (the holder reads not-delinquent, N6 sees a fresh own lastVote, the spare holds by design).
# Drives the REAL check_identity_collision (both daemons) with curl/date mocked at the I/O boundary.
#   (C-a) non-self endpoint on an external vantage ×2 CONSECUTIVE → 🚨 page (with both endpoints)
#   (C-b) ×1 non-self, then self again → strikes reset → NO page (gossip flap tolerance)
#   (C-c) only-while-STAKED: an unstaked node never strikes/pages on the same inputs
#   (C-d) NEVER demotes: identity untouched, switch/give-back never called, even while paging
#   (C-e) ambiguity (LOCAL own-endpoint unreadable / no external answer) → counts neither way
#   (C-f) throttle: within COLLISION_CHECK_INTERVAL the check does not even evaluate
#   (C-g) NON-VACUOUS: v0.6.8 baseline has ZERO check_identity_collision (the detector is new) and
#         both v0.6.9 MAIN LOOP STAKED branches call it

set +e
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIMARY="$DIR/solana-primary-failover.sh"
STANDBY="$DIR/solana-standby-failover.sh"
V068P="$DIR/../../0.6.8/failover-v0.6.8/solana-primary-failover.sh"
[[ -f "$PRIMARY" && -f "$STANDBY" ]] || { echo "  ❌ scripts not found"; exit 1; }

echo "============================================="
echo "  Collision detector (v0.6.9 M5) — detection-only"
echo "============================================="

for SCRIPT in "$PRIMARY" "$STANDBY"; do
  NAME=$(basename "$SCRIPT" | sed 's/solana-\(.*\)-failover.sh/\1/' | tr '[:lower:]' '[:upper:]')

  SRC=$(mktemp); sed -n '1,/MAIN LOOP/p' "$SCRIPT" > "$SRC"
  # subshell per script so the two sourcings don't collide
  RESULT=$(
    set +e
    # shellcheck disable=SC1090
    source "$SRC"
    STAKED_PUBKEY="S1"; UNSTAKED_PUBKEY="U1"; VOTE_PUBKEY="V1"
    LOCAL_RPC="http://mock-local"; TIER2_RPC="http://mock-t2"; TIER3_RPC="http://mock-t3"
    COLLISION_CHECK_INTERVAL=60; ALERT_THROTTLE=600; TG_ENABLED=false; DRY_RUN=false
    log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }
    send_telegram(){ return 0; }; send_webhook(){ :; }; save_state(){ :; }; sleep(){ :; }
    _SIM_NOW=1700000000
    date(){ [[ "$1" == "+%s" ]] && { echo "$_SIM_NOW"; return 0; }; command date "$@"; }
    _PAGES=0; _PAGE_TXT=""
    alert(){ _PAGES=$((_PAGES+1)); _PAGE_TXT="$1 :: $3"; }
    alert_warn(){ :; }; alert_info(){ :; }
    _DEMOTES=0
    switch_to_unstaked(){ _DEMOTES=$((_DEMOTES+1)); }
    give_back_identity(){ _DEMOTES=$((_DEMOTES+1)); }
    # curl mock: LOCAL getClusterNodes → own endpoint $_OWN_EP; T2/T3 → $_EXT_EP (empty = no answer)
    _OWN_EP="9.9.9.9:8001"; _EXT_EP="9.9.9.9:8001"
    curl(){
        local url="" d=""
        # v0.6.9 (B3): if/elif dispatch, NOT `case … )`. A `case` with `)` patterns inside this
        # RESULT=$( … ) command substitution fails to PARSE on bash 3.2 (the macOS test box), which
        # silently skipped the ENTIRE M5 suite there (34/35, not the claimed 35/35). Case-free = runs on 3.2.
        while [[ $# -gt 0 ]]; do
            if [[ "$1" == "-d" ]]; then d="$2"; shift 2
            elif [[ "$1" == http* ]]; then url="$1"; shift
            else shift
            fi
        done
        [[ "$d" == *getClusterNodes* ]] || return 7
        if [[ "$url" == "$LOCAL_RPC" ]]; then
            [[ -z "$_OWN_EP" ]] && { printf '{"result":[]}'; return 0; }
            printf '{"result":[{"pubkey":"S1","gossip":"%s"}]}' "$_OWN_EP"; return 0
        fi
        [[ -z "$_EXT_EP" ]] && { printf '{"result":[]}'; return 0; }
        printf '{"result":[{"pubkey":"S1","gossip":"%s"}]}' "$_EXT_EP"; return 0
    }
    tick(){ _SIM_NOW=$(( _SIM_NOW + 61 )); }   # past COLLISION_CHECK_INTERVAL each call
    r=""

    # (C-a) 2 consecutive non-self strikes → page with both endpoints
    CURRENT_IDENTITY="S1"; _collision_strikes=0; _last_collision_check=0; _last_collision_alert=0; _PAGES=0
    _EXT_EP="1.2.3.4:8001"
    tick; check_identity_collision; p1=$_PAGES
    tick; check_identity_collision; p2=$_PAGES
    if [[ $p1 -eq 0 && $p2 -eq 1 && "$_PAGE_TXT" == *"1.2.3.4:8001"* && "$_PAGE_TXT" == *"9.9.9.9:8001"* && "$_PAGE_TXT" == *"SEEN ELSEWHERE"* ]]; then
        r+="a=ok;"; else r+="a=BAD(p1=$p1,p2=$p2,txt=$_PAGE_TXT);"
    fi

    # (C-b) 1 strike then self → reset, no page
    CURRENT_IDENTITY="S1"; _collision_strikes=0; _last_collision_check=0; _last_collision_alert=0; _PAGES=0
    _EXT_EP="1.2.3.4:8001"; tick; check_identity_collision
    _EXT_EP="9.9.9.9:8001"; tick; check_identity_collision
    _EXT_EP="1.2.3.4:8001"; tick; check_identity_collision   # a fresh single strike, still no page
    if [[ $_PAGES -eq 0 && $_collision_strikes -eq 1 ]]; then r+="b=ok;"; else r+="b=BAD(pages=$_PAGES,strikes=$_collision_strikes);"; fi

    # (C-c) only-while-STAKED
    CURRENT_IDENTITY="U1"; _collision_strikes=0; _last_collision_check=0; _PAGES=0
    _EXT_EP="1.2.3.4:8001"; tick; check_identity_collision; tick; check_identity_collision
    if [[ $_PAGES -eq 0 && $_collision_strikes -eq 0 ]]; then r+="c=ok;"; else r+="c=BAD(pages=$_PAGES,strikes=$_collision_strikes);"; fi

    # (C-d) never demotes — identity untouched while paging
    CURRENT_IDENTITY="S1"; _collision_strikes=0; _last_collision_check=0; _last_collision_alert=0; _PAGES=0; _DEMOTES=0
    _EXT_EP="1.2.3.4:8001"; tick; check_identity_collision; tick; check_identity_collision
    if [[ $_PAGES -eq 1 && $_DEMOTES -eq 0 && "$CURRENT_IDENTITY" == "S1" ]]; then r+="d=ok;"; else r+="d=BAD(pages=$_PAGES,demotes=$_DEMOTES,id=$CURRENT_IDENTITY);"; fi

    # (C-e) ambiguity holds the counter (neither strike nor clear)
    CURRENT_IDENTITY="S1"; _collision_strikes=1; _last_collision_check=0; _PAGES=0
    _OWN_EP=""; tick; check_identity_collision            # own endpoint unreadable
    s_own=$_collision_strikes
    _OWN_EP="9.9.9.9:8001"; _EXT_EP=""; tick; check_identity_collision   # externals silent
    s_ext=$_collision_strikes
    if [[ $s_own -eq 1 && $s_ext -eq 1 && $_PAGES -eq 0 ]]; then r+="e=ok;"; else r+="e=BAD(own=$s_own,ext=$s_ext,pages=$_PAGES);"; fi

    # (C-f) throttle: second call inside the interval does not evaluate
    CURRENT_IDENTITY="S1"; _collision_strikes=0; _last_collision_check=0; _PAGES=0
    _EXT_EP="1.2.3.4:8001"; tick; check_identity_collision
    _SIM_NOW=$(( _SIM_NOW + 5 )); check_identity_collision   # +5s < 60s interval
    if [[ $_collision_strikes -eq 1 ]]; then r+="f=ok;"; else r+="f=BAD(strikes=$_collision_strikes);"; fi

    printf '%s' "$r"
  )
  rm -f "$SRC"

  echo ""
  echo "─── [$NAME] ───"
  [[ "$RESULT" == *"a=ok;"* ]] && ok "[$NAME] (C-a) 2 consecutive non-self strikes → 🚨 page with BOTH endpoints" || bad "[$NAME] (C-a) $RESULT"
  [[ "$RESULT" == *"b=ok;"* ]] && ok "[$NAME] (C-b) 1 strike then self → reset, no page (flap tolerated)"        || bad "[$NAME] (C-b) $RESULT"
  [[ "$RESULT" == *"c=ok;"* ]] && ok "[$NAME] (C-c) only-while-STAKED: unstaked node never strikes/pages"        || bad "[$NAME] (C-c) $RESULT"
  [[ "$RESULT" == *"d=ok;"* ]] && ok "[$NAME] (C-d) NEVER demotes: identity untouched, no switch/give-back call" || bad "[$NAME] (C-d) $RESULT"
  [[ "$RESULT" == *"e=ok;"* ]] && ok "[$NAME] (C-e) ambiguity counts neither way (strikes held)"                 || bad "[$NAME] (C-e) $RESULT"
  [[ "$RESULT" == *"f=ok;"* ]] && ok "[$NAME] (C-f) COLLISION_CHECK_INTERVAL throttles evaluation"               || bad "[$NAME] (C-f) $RESULT"
done

# ── (C-g) non-vacuous: new in v0.6.9 + wired into both STAKED branches ─────────────────────────
echo ""; echo "─── (C-g) detector is NEW (v0.6.8 = zero refs) and wired into both main loops ───"
if [[ -f "$V068P" ]]; then
    v8=$(grep -c 'check_identity_collision' "$V068P")
    [[ $v8 -eq 0 ]] && ok "(C-g1) v0.6.8 primary has 0 check_identity_collision refs → M5 genuinely new" \
                    || bad "(C-g1) v0.6.8 already had it ($v8)"
else
    ok "(C-g1) v0.6.8 baseline not present to compare (skipped)"
fi
np=$(sed -n '/MAIN LOOP/,$p' "$PRIMARY" | grep -c 'check_identity_collision')
ns=$(sed -n '/MAIN LOOP/,$p' "$STANDBY" | grep -c 'check_identity_collision')
[[ $np -ge 1 && $ns -ge 1 ]] \
    && ok "(C-g2) both MAIN LOOP STAKED branches call check_identity_collision (primary=$np standby=$ns)" \
    || bad "(C-g2) main-loop wiring missing (primary=$np standby=$ns)"

echo ""
echo "============================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "============================================="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
