#!/bin/bash
# Business-hours control for the Blent Cover Reserve Fund's covered pool.
# See cover-reserve.txt.
#
#   cover-hours.sh check     deposits vs fund; exit 0 if covered
#   cover-hours.sh tick      cron, every 5 min: frozen outside hours,
#                            opened in hours only if covered
#   cover-hours.sh hold      incident: freeze now, tick won't reopen
#   cover-hours.sh release   remove the hold
#   cover-hours.sh freeze    freeze now, no hold (go-live: setup -> 4)
#
# The pool admin is the pool-status-manager (MANAGER).  Status changes are
# sent to the manager's set_status, signed by the keeper's OPERATOR key
# (SOURCE, a stellar keys identity; only the blnt-keeper user has it), so
# tick, hold and freeze run as that user:
#   sudo -u blnt-keeper -H /opt/blnt-keeper/cover-hours.sh hold
# check and release need no key.
#
# Cover rule: fund USDC >= COVER_DEPOSITS x deposits(USD)
#                         + COVER_BACKSTOP x backstop active value(USD)
#
# tick only prints when it acts or something is wrong, so cron mail is
# the alert.

set -euo pipefail
cd "$(dirname "$0")"

# --- config -----------------------------------------------------------
SOURCE=${SOURCE:-operator}       # keeper identity (stellar keys) that signs
OPERATOR=GAF6YOV7NXCTGR6U2CKZURLD5I7EB4AL5HLVYI3E3VR3C5A2FAY7LT43   # its address
MANAGER=CCP7DMV4WCVPH2C6ZETXCBFXDPQRLN27CQEAHVILEFWUM7QCG6DMIVDQ    # pool admin
POOL=${POOL:-CCH3BNZWTTBB2AKX6NT5OGKQSWP4UNBIKRTRMRDKKJLPMFKULHQZC3XD}   # Blent Covered Pool
FUND=${FUND:-GDA5JJFUAGFBNT4BMEGASY7EWBJFOWL2VBXMYY6QKCEOZMXHX6BBXYOB}   # fund multisig (read only)
ORACLE=CDN7JD6SP32RZHB3DHK4S4AWCCQF6GYIUO455UCR4RGRZILZDRD24N36
BACKSTOP=CAHCUKBPTW5DR5RNXOHCTJD5U76A6EEZXYZAQFRQEEQRXQ3CRUZ6Z3MO
USDC_ISSUER=GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN
HORIZON=https://horizon.stellar.org

COVER_DEPOSITS=0.9
COVER_BACKSTOP=${COVER_BACKSTOP:-0}   # backstop not covered (DECISION 2026-11-17); keep 0

TZONE=America/New_York
DAYS="1 2 3 4 5"                 # date +%u, Mon=1
OPEN=0930                        # HHMM ET, NYSE hours
CLOSE=1600
HOLIDAYS=cover-holidays.txt      # "YYYY-MM-DD" closed all day,
                                 # "YYYY-MM-DD HHMM" early close; # comments
MAX_PRICE_AGE=1800               # seconds

STATE_DIR=${STATE_DIR:-.}        # writable; the keeper sets its own home
HOLD=$STATE_DIR/cover-hours.hold
STATE=$STATE_DIR/cover-hours.state   # date of last reported failed check
# ----------------------------------------------------------------------

die() { echo "cover-hours: $*" >&2; exit 2; }
[ -n "$POOL" ] || die "POOL not set"
[ -n "$FUND" ] || die "FUND not set"

view() {    # read-only; any funded account works as the simulation source
    stellar contract invoke --source-account "$OPERATOR" --network mainnet \
        --send no --id "$@" 2>/dev/null | tail -1
}
send() {
    stellar contract invoke --source-account "$SOURCE" --network mainnet \
        --inclusion-fee 10000000 --id "$@"
}

pool_status() {
    local s
    s=$(view "$POOL" -- get_config | jq -r .status) || true
    [[ "$s" =~ ^[0-9]$ ]] || die "can't read pool status"
    echo "$s"
}

set_status() {    # set_status <n>: check roles, simulate, send, verify
    local n=$1 a
    a=$(stellar keys address "$SOURCE" 2>/dev/null) || true
    [ "$a" = "$OPERATOR" ] || die "key '$SOURCE' is '$a', not the operator $OPERATOR (run as blnt-keeper)"
    a=$(view "$POOL" -- get_admin | tr -d '"')
    [ "$a" = "$MANAGER" ] || die "pool admin is '$a', not the manager $MANAGER"
    a=$(view "$MANAGER" -- get_operator | tr -d '"')
    [ "$a" = "$OPERATOR" ] || die "manager operator is '$a', not $OPERATOR"
    # (simulation does not check auth; the real send does)
    send "$MANAGER" --send no -- set_status --caller "$OPERATOR" --pool "$POOL" \
        --pool_status "$n" >/dev/null 2>&1 || die "set_status $n simulation failed"
    send "$MANAGER" -- set_status --caller "$OPERATOR" --pool "$POOL" \
        --pool_status "$n" 2>&1 | grep -E 'https://|rror' || true
    [ "$(pool_status)" = "$n" ] || die "status is not $n after set_status"
    echo "$(date -Is) pool status -> $n"
}

deposits_usd() {    # prints one line per reserve, then "TOTAL <usd>"
    local now total=0 a r p usd age
    now=$(date +%s)
    for a in $(view "$POOL" -- get_reserve_list | jq -r '.[]'); do
        r=$(view "$POOL" -- get_reserve --asset "$a")
        p=$(view "$ORACLE" -- lastprice --asset "{\"Stellar\":\"$a\"}")
        [ -n "$r" ] || die "can't read reserve $a"
        echo "$p" | jq -e '.price' >/dev/null 2>&1 || die "no price for $a"
        age=$(( now - $(echo "$p" | jq -r .timestamp) ))
        [ "$age" -le "$MAX_PRICE_AGE" ] || die "price for $a is ${age}s old"
        usd=$(echo "$r" | jq -r --argjson p "$p" '
            (.data.b_supply|tonumber) * (.data.b_rate|tonumber) / 1e12
            / pow(10; .config.decimals) * ($p.price|tonumber) / 1e7')
        printf '  %s  %12.2f\n' "$a" "$usd" >&2
        total=$(jq -n "$total + $usd")
    done
    echo "$total"
}

fund_usdc() {
    curl -sf "$HORIZON/accounts/$FUND" | jq -r --arg i "$USDC_ISSUER" '
        [.balances[] | select(.asset_code=="USDC" and .asset_issuer==$i)
         | .balance | tonumber] | add // empty'
}

backstop_usd() {
    view "$BACKSTOP" -- pool_data --pool "$POOL" \
        | jq -r '(.active_value|tonumber) / 1e7'
}

check() {    # exit 0 covered, 1 short, 2 couldn't read
    local dep fund bs need
    echo "deposits (USD):" >&2
    dep=$(deposits_usd) || die "can't read deposits"
    fund=$(fund_usdc) || true
    [ -n "$fund" ] || die "can't read fund USDC balance"
    bs=0
    if [ "$(jq -n "$COVER_BACKSTOP > 0")" = true ]; then
        bs=$(backstop_usd) || true
        [ -n "$bs" ] || die "can't read backstop value"
    fi
    need=$(jq -n "$COVER_DEPOSITS * $dep + $COVER_BACKSTOP * $bs")
    printf 'deposits %10.2f  x %s\n' "$dep" "$COVER_DEPOSITS" >&2
    [ "$bs" = 0 ] || printf 'backstop %10.2f  x %s\n' "$bs" "$COVER_BACKSTOP" >&2
    printf 'required %10.2f\nfund     %10.2f  -> ' "$need" "$fund" >&2
    if [ "$(jq -n "$fund >= $need")" = true ]; then
        echo "covered" >&2; return 0
    fi
    printf 'SHORT by %.2f\n' "$(jq -n "$need - $fund")" >&2; return 1
}

in_hours() {
    local d hm today close=$CLOSE h
    d=$(TZ=$TZONE date +%u); hm=$(TZ=$TZONE date +%H%M); today=$(TZ=$TZONE date +%F)
    [[ " $DAYS " == *" $d "* ]] || return 1
    [ -f "$HOLIDAYS" ] || die "missing $HOLIDAYS"
    h=$(sed 's/#.*//' "$HOLIDAYS" | awk -v t="$today" '$1==t {print ($2=="" ? "closed" : $2); exit}')
    [ "$h" != closed ] || return 1
    [ -z "$h" ] || close=$h
    [ "$((10#$hm))" -ge "$((10#$OPEN))" ] && [ "$((10#$hm))" -lt "$((10#$close))" ]
}

tick() {
    local s today out
    s=$(pool_status)
    case $s in
        6) return 0 ;;                 # setup: not live yet
        5) echo "pool is Frozen by backstop withdrawals (status 5)"; return 0 ;;
    esac
    if ! in_hours || [ -f "$HOLD" ]; then
        [ "$s" = 4 ] || set_status 4
        return 0
    fi
    [ "$s" = 4 ] || return 0           # open (or on ice by q4w): leave it
    today=$(TZ=$TZONE date +%F)
    if out=$(check 2>&1); then
        set_status 0
        echo "$out"
        rm -f "$STATE"
    else
        if [ "$(cat "$STATE" 2>/dev/null)" != "$today" ]; then
            echo "pool stays FROZEN: opening check failed"
            echo "$out"
            echo "$today" > "$STATE"
        fi
        return 1
    fi
}

case "${1:-}" in
    check)   check ;;
    tick)    tick ;;
    hold)    touch "$HOLD"; [ "$(pool_status)" = 4 ] || set_status 4
             echo "hold set; tick will not reopen until: $0 release" ;;
    release) rm -f "$HOLD"; echo "hold released" ;;
    freeze)  [ "$(pool_status)" = 4 ] && echo "already frozen (4)" || set_status 4 ;;
    *)       sed -n '2,23p' "$0"; exit 2 ;;
esac
