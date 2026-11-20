#!/bin/bash
# Weekly supply-cap revision for the Blent Covered Pool (cover-reserve.txt,
# "Weekly cap revision").  The pool admin is the pool-status-manager, owned
# by the fund multisig, so a cap change is a fund transaction signed in
# Refractor; applying it 7 days later is permissionless.
#
#   ./revise-caps-covered.sh                    report + suggested caps (read-only)
#   ./revise-caps-covered.sh build XLM=200 USDC=50 [--force]
#                                               fund XDRs that queue the new caps
#   ./revise-caps-covered.sh apply              set_reserve every queued change whose
#                                               7 days are up (sends, from $SOURCE)
#
# Rule: limit = fund USDC / 0.9; the caps' total value, with XLM +30%
# (STRESS below), must stay under the limit.  build refuses caps that
# break it unless --force.
#
# build writes one XDR per asset to xdr/caps-<date>-<n>-<asset>.xdr and
# prints them.  Soroban allows one contract call per transaction, so each
# asset is its own fund transaction; they get consecutive sequence numbers
# and MUST be submitted in order (n = 1, 2, ...), and no other fund
# transaction may land in between.  Each sends the reserve's whole current
# config with only supply_cap changed (other changes would reset ir_mod).
#
# One queued change per asset: a second queue for the same asset fails
# until the first is applied (apply) or cancelled (manager
# cancel_set_reserve, another fund XDR; not built here).

set -eo pipefail
cd "$(dirname "$0")"

FUND=GDA5JJFUAGFBNT4BMEGASY7EWBJFOWL2VBXMYY6QKCEOZMXHX6BBXYOB
POOL=CCH3BNZWTTBB2AKX6NT5OGKQSWP4UNBIKRTRMRDKKJLPMFKULHQZC3XD
MANAGER=CCP7DMV4WCVPH2C6ZETXCBFXDPQRLN27CQEAHVILEFWUM7QCG6DMIVDQ
ORACLE=CDN7JD6SP32RZHB3DHK4S4AWCCQF6GYIUO455UCR4RGRZILZDRD24N36
USDC_ISSUER=GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN
HORIZON=https://horizon.stellar.org
SOURCE=${SOURCE:-xbull}          # apply only: pays the fee; set_reserve is permissionless
COVER=0.9
FEE=1000000                      # inclusion fee, stroops (0.1 XLM max)
# name address stress   (stress = price headroom when sizing caps)
ASSETS="XLM CAS3J7GYLGXMF6TDJBBYYSE3HQ6BBSMLNUQ34T6TZMYMW2EVH34XOWMA 1.3
USTRY CBLV4ATSIWU67CFSQU2NVRKINQIKUZ2ODSZBUJTJ43VJVRSBTZYOPNUR 1.0
USDC CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75 1.0"

log() { echo "$@" >&2; }
die() { log "*** $*"; exit 1; }
view() {
    stellar contract invoke --source-account $FUND --network mainnet --send no \
        --id "$@" 2>/dev/null | tail -1 || true
}
queued() {    # queued <asset>: the pending QueuedReserveInit as JSON, or empty
    local k
    k=$(echo "{\"vec\":[{\"symbol\":\"ResInit\"},{\"address\":\"$1\"}]}" | stellar xdr encode --type ScVal)
    stellar contract read --network mainnet --id $POOL --durability temporary \
        --key-xdr "$k" --output json 2>/dev/null || true
}

# Collect everything into one JSON document for the python below.
state() {
    local fund name addr stress res price q
    fund=$(curl -sf $HORIZON/accounts/$FUND | jq -r --arg i $USDC_ISSUER \
        '[.balances[] | select(.asset_code=="USDC" and .asset_issuer==$i) | .balance|tonumber] | add // 0') \
        || die "can't read fund"
    echo "{\"fund\": $fund, \"pdec\": $(view $ORACLE -- decimals), \"reserves\": ["
    local first=1
    while read -r name addr stress; do
        res=$(view $POOL -- get_reserve --asset $addr)
        price=$(view $ORACLE -- lastprice --asset "{\"Stellar\":\"$addr\"}")
        [ -n "$res" ] || die "can't read reserve $name"
        echo "$price" | jq -e .price >/dev/null 2>&1 || die "no price for $name"
        q=$(queued $addr | jq -c . 2>/dev/null || true)
        [ $first = 1 ] || echo ","; first=0
        echo "{\"name\":\"$name\",\"addr\":\"$addr\",\"stress\":$stress,\"res\":$res,\"price\":$price,\"queued\":${q:-null}}"
    done <<< "$ASSETS"
    echo "]}"
}

report() {    # report <state.json> [NAME=CAP ...]: prints table; exit 1 if the caps break the rule
    COVER=$COVER python3 -I - "$@" <<'EOF'
import json, sys, re, math, time
st = json.load(open(sys.argv[1]))
new = {}
for a in sys.argv[2:]:
    n, v = a.split("=", 1)
    new[n.upper()] = float(v)
import os
fund, cover = st["fund"], float(os.environ["COVER"])
limit = fund / cover
pd = 10 ** st["pdec"]

def find(o, key):    # first value of key anywhere in o
    if isinstance(o, dict):
        if key in o: return o[key]
        o = list(o.values())
    if isinstance(o, list):
        for x in o:
            r = find(x, key)
            if r is not None: return r
    return None

rows, tot_v, tot_cap, tot_stress = [], 0, 0, 0
for r in st["reserves"]:
    c, d = r["res"]["config"], r["res"]["data"]
    dec = 10 ** c["decimals"]
    p = int(r["price"]["price"]) / pd
    supplied = int(d["b_supply"]) * int(d["b_rate"]) / 1e12 / dec
    cap = int(c["supply_cap"]) / dec
    use = new.get(r["name"], cap)
    q = r["queued"]
    qcap = find(q, "supply_cap") if q else None
    qt = find(q, "unlock_time") if q else None
    rows.append((r["name"], cap, use, supplied, p, qcap and int(qcap) / dec, qt and int(qt)))
    tot_v += supplied * p
    tot_cap += use * p
    tot_stress += use * p * r["stress"]

print(f"fund {fund:.2f} USDC  ->  deposit limit {limit:.2f} (fund / {cover})")
print(f"deposits now {tot_v:.2f}  ({100 * tot_v / limit:.0f}% of limit)\n")
print(f"{'asset':6} {'cap':>10} {'new cap':>10} {'supplied':>10} {'price':>10} {'cap value':>10}  queued")
for n, cap, use, sup, p, qc, qt in rows:
    qs = "-" if qc is None else f"{qc:g} (unlocks {time.strftime('%Y-%m-%d %H:%M', time.localtime(qt))})"
    nc = "" if use == cap else f"{use:g}"
    print(f"{n:6} {cap:10g} {nc:>10} {sup:10.2f} {p:10.4f} {use * p:10.2f}  {qs}")
    if use < sup:
        print(f"       note: {n} cap below current supply: new supply blocked until it falls")
print(f"\ncaps total {tot_cap:.2f}, with stress {tot_stress:.2f}  vs limit {limit:.2f}"
      f"  ->  {'OK' if tot_stress <= limit else 'OVER'}")

if not new:
    k = limit / tot_stress if tot_stress else 0
    def floor2(x):    # round down to 2 significant figures
        if x <= 0: return 0
        e = 10 ** (math.floor(math.log10(x)) - 1)
        return math.floor(x / e) * e
    sug = []
    for (n, cap, *_), r in zip(rows, st["reserves"]):
        s = floor2(cap * k)
        sug.append(f"{n}={s:g}")
    print("\nsuggested (current caps scaled to the limit, rounded down):")
    print("  ./revise-caps-covered.sh build " + " ".join(sug))
sys.exit(0 if tot_stress <= limit else 1)
EOF
}

build() {
    local force=no args=() a n v addr tmp base i out date
    for a in "$@"; do
        case $a in --force) force=yes ;; *=*) args+=("$a") ;; *) die "bad argument $a" ;; esac
    done
    [ ${#args[@]} -gt 0 ] || die "usage: $0 build XLM=200 [USTRY=..] [USDC=..] [--force]"
    for a in "${args[@]}"; do
        n=${a%%=*}; v=${a#*=}
        grep -q "^${n^^} " <<< "$ASSETS" || die "unknown asset $n"
        [[ "$v" =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "bad cap $a"
    done

    tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
    state > "$tmp"
    if ! report "$tmp" "${args[@]}" >&2; then
        [ $force = yes ] || die "new caps break the limit; nothing built (--force to override)"
        log "*** --force: building caps over the limit"
    fi
    log

    base=$(curl -sf $HORIZON/accounts/$FUND | jq -r .sequence) || die "can't read fund sequence"
    date=$(date +%Y%m%d); mkdir -p xdr; i=0
    for a in "${args[@]}"; do
        n=${a%%=*}; n=${n^^}; v=${a#*=}; i=$((i + 1))
        addr=$(awk -v n="$n" '$1==n {print $2}' <<< "$ASSETS")
        jq -e --arg a "$addr" '.reserves[] | select(.addr==$a) | .queued == null' "$tmp" >/dev/null \
            || die "$n already has a queued change; apply or cancel it first"
        META=$(jq -c --arg a "$addr" --arg v "$v" '.reserves[] | select(.addr==$a) | .res.config
            | .supply_cap = (($v|tonumber) * pow(10; .decimals) | floor | tostring)' "$tmp")
        out=xdr/caps-$date-$i-$n.xdr
        stellar contract invoke --source-account $FUND --network mainnet --build-only \
            --inclusion-fee $FEE --id $MANAGER -- queue_set_reserve \
            --pool $POOL --asset $addr --metadata "$META" \
          | stellar tx simulate --network mainnet --source-account $FUND \
          | stellar tx decode \
          | jq -c --argjson s "$((base + i))" '.tx.tx.seq_num = $s' \
          | stellar tx encode > "$out" \
            || die "build/simulate failed for $n"
        log "== $i/${#args[@]}  $n supply_cap -> $v   (seq $((base + i)), $out)"
        log "   metadata $META"
        cat "$out"
        log
    done
    log "Submit in Refractor IN ORDER (1, 2, ...), each after the previous lands;"
    log "no other fund transaction in between.  2 of 3 fund signatures each."
    log "In 7 days: ./revise-caps-covered.sh apply"
}

apply() {
    local name addr stress q ut now sent=0
    now=$(date +%s)
    while read -r name addr stress; do
        q=$(queued $addr)
        [ -n "$q" ] || { log "$name: nothing queued"; continue; }
        ut=$(echo "$q" | jq '[.. | .unlock_time? // empty | tonumber] | first')
        if [ "$ut" -gt "$now" ]; then
            log "$name: queued, unlocks $(date -d @"$ut" '+%F %H:%M') (not yet)"; continue
        fi
        stellar contract invoke --source-account $SOURCE --network mainnet --send no \
            --id $POOL -- set_reserve --asset $addr >/dev/null 2>&1 \
            || die "$name: set_reserve simulation failed"
        read -r -p "$name: unlocked; apply with set_reserve (from $SOURCE)? [y/N] " ok < /dev/tty
        [ "$ok" = y ] || continue
        stellar contract invoke --source-account $SOURCE --network mainnet \
            --inclusion-fee 10000000 --id $POOL -- set_reserve --asset $addr
        sent=$((sent + 1))
    done <<< "$ASSETS"
    log "applied $sent"
}

case "${1:-}" in
    "")     tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT; state > "$tmp"; report "$tmp" || true ;;
    build)  shift; build "$@" ;;
    apply)  apply ;;
    *)      sed -n '2,27p' "$0"; exit 2 ;;
esac
