#!/bin/bash
# One-off: step 2 of ../pool-deploy.txt -- add the 10 reserves to the
# YieldBlent pool.  Not tracked (*.local.sh).  Delete when done.
#
# The pool is in status 6 (setup), so there's no timelock: each
# queue_set_reserve can be followed right away by set_reserve.  The
# reserve index is the position in the pool's reserve list, so reserves
# MUST be added in this order; the script checks each returned index.
#
# Configs copied from "Reserve configs for the new pool" in
# ../pool-deploy.txt on 2026-11-05.
#
# Re-runnable: reserves already in the pool are skipped.  Simulates every
# queue_set_reserve first and asks before sending.

set -e
cd "$(dirname "$0")"

SOURCE=xbull                     # pool admin
POOL=CAUTPSQDAJEUV5XEU3EXFVYRGDJLEJGVTFJCFZCSPTDCREAMZ573VF4D
ORACLE=CDN7JD6SP32RZHB3DHK4S4AWCCQF6GYIUO455UCR4RGRZILZDRD24N36

# name address config-json
RESERVES='
XLM CAS3J7GYLGXMF6TDJBBYYSE3HQ6BBSMLNUQ34T6TZMYMW2EVH34XOWMA {"index":0,"decimals":7,"c_factor":7500000,"l_factor":7500000,"util":5000000,"max_util":7000000,"r_base":100000,"r_one":400000,"r_two":3000000,"r_three":50000000,"reactivity":20,"supply_cap":"10000000000000000","enabled":true}
USDC CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75 {"index":1,"decimals":7,"c_factor":9500000,"l_factor":9500000,"util":8000000,"max_util":9500000,"r_base":300000,"r_one":400000,"r_two":1200000,"r_three":50000000,"reactivity":20,"supply_cap":"2000000000000000","enabled":true}
EURC CDTKPWPLOURQA2SGTKTUQOWRCBZEORB4BWBOMJ3D3ZTQQSGE5F6JBQLV {"index":2,"decimals":7,"c_factor":9000000,"l_factor":9000000,"util":7500000,"max_util":9000000,"r_base":300000,"r_one":400000,"r_two":1200000,"r_three":50000000,"reactivity":20,"supply_cap":"100000000000000","enabled":true}
AQUA CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK {"index":3,"decimals":7,"c_factor":4000000,"l_factor":4000000,"util":4000000,"max_util":7000000,"r_base":100000,"r_one":400000,"r_two":3000000,"r_three":50000000,"reactivity":20,"supply_cap":"1800000000000000","enabled":true}
USDGLO CB226ZOEYXTBPD3QEGABTJYSKZVBP2PASEISLG3SBMTN5CE4QZUVZ3CE {"index":4,"decimals":7,"c_factor":9000000,"l_factor":9000000,"util":7500000,"max_util":9000000,"r_base":300000,"r_one":400000,"r_two":1200000,"r_three":50000000,"reactivity":20,"supply_cap":"1000000000000","enabled":true}
USTRY CBLV4ATSIWU67CFSQU2NVRKINQIKUZ2ODSZBUJTJ43VJVRSBTZYOPNUR {"index":5,"decimals":7,"c_factor":6000000,"l_factor":6000000,"util":5000000,"max_util":8000000,"r_base":100000,"r_one":200000,"r_two":1000000,"r_three":50000000,"reactivity":20,"supply_cap":"700000000000","enabled":true}
CETES CAL6ER2TI6CTRAY6BFXWNWA7WTYXUXTQCHUBCIBU5O6KM3HJFG6Z6VXV {"index":6,"decimals":7,"c_factor":6000000,"l_factor":6000000,"util":5000000,"max_util":8000000,"r_base":100000,"r_one":300000,"r_two":1200000,"r_three":50000000,"reactivity":20,"supply_cap":"12000000000000","enabled":true}
PYUSD CCCRWH6Q3FNP3I2I57BDLM5AFAT7O6OF6GKQOC6SSJNDAVRZ57SPHGU2 {"index":7,"decimals":7,"c_factor":9000000,"l_factor":9000000,"util":7500000,"max_util":9000000,"r_base":300000,"r_one":400000,"r_two":1200000,"r_three":50000000,"reactivity":20,"supply_cap":"50000000000000","enabled":true}
USDT0 CBSJZEIO5C7KC2SF3MKSNXXJSW5G3VTNBX4ATMKUI3B2MR4JKM4R26YF {"index":8,"decimals":7,"c_factor":9500000,"l_factor":9500000,"util":8000000,"max_util":9500000,"r_base":300000,"r_one":400000,"r_two":1200000,"r_three":50000000,"reactivity":20,"supply_cap":"100000000000000","enabled":true}
SolvBTC CBIJBDNZNF4X35BJ4FFZWCDBSCKOP5NB4PLG4SNENRMLAPYG4P5FM6VN {"index":9,"decimals":8,"c_factor":7500000,"l_factor":7500000,"util":5000000,"max_util":7000000,"r_base":100000,"r_one":400000,"r_two":3000000,"r_three":50000000,"reactivity":20,"supply_cap":"2000000000","enabled":true}
'

inv() {
    stellar contract invoke --source-account $SOURCE --network mainnet \
        --inclusion-fee 10000000 "$@"
}
view() { inv --send no --id "$@" 2>&1 | tail -1; }

each() {    # each <fn>: call fn name addr json index for every reserve
    local i=0
    while read -r name addr json; do
        [ -n "$name" ] || continue
        "$1" "$name" "$addr" "$json" $i
        i=$((i + 1))
    done <<< "$RESERVES"
}

echo "== 0. pool state"
CONFIG=$(view $POOL -- get_config)
LIST=$(view $POOL -- get_reserve_list)
echo "config   $CONFIG"
echo "reserves $LIST"
case "$CONFIG" in *'"status":6'*) ;; *)
    echo "*** pool is not in status 6 (setup): every reserve change would"
    echo "*** wait a week.  Stopping."; exit 1;; esac

echo
echo "== 1. checks + simulate queue_set_reserve"
check() {
    local name=$1 addr=$2 json=$3 i=$4
    case "$LIST" in *$addr*) printf '%-8s already added, skip\n' $name; return;; esac
    local idx dec tokdec price
    idx=$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["index"])' "$json")
    dec=$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["decimals"])' "$json")
    tokdec=$(view $addr -- decimals)
    price=$(view $ORACLE -- lastprice --asset "{\"Stellar\":\"$addr\"}")
    [ "$idx" = $i ] || { echo "*** $name: config index $idx, list position $i"; exit 1; }
    [ "$dec" = "$tokdec" ] || { echo "*** $name: config decimals $dec, token $tokdec"; exit 1; }
    case "$price" in *'"price"'*) ;; *) echo "*** $name: no oracle price: $price"; exit 1;; esac
    inv --send no --id $POOL -- queue_set_reserve --asset $addr --metadata "$json" > /dev/null 2>/tmp/qsr.$$ \
        || { echo "*** $name: queue_set_reserve simulation failed:"; tail -3 /tmp/qsr.$$; exit 1; }
    printf '%-8s index %s, decimals %s, price %s, simulation ok\n' $name $i $dec "$price"
}
each check
rm -f /tmp/qsr.$$

echo
read -p "Add these reserves to $POOL (2 transactions each)? [y/N] " ok
[ "$ok" = y ] || { echo "stopped; nothing sent"; exit 0; }

echo "== 2. queue_set_reserve + set_reserve (sends)"
add() {
    local name=$1 addr=$2 json=$3 i=$4
    case "$LIST" in *$addr*) return;; esac
    echo "-- $name"
    inv --send yes --id $POOL -- queue_set_reserve --asset $addr --metadata "$json"
    local got
    got=$(inv --send yes --id $POOL -- set_reserve --asset $addr | tail -1)
    if [ "$got" != $i ]; then
        echo "*** $name got index $got, expected $i.  Stopping."; exit 1
    fi
    echo "$name -> index $got"
}
each add

echo
echo "== 3. verify"
echo "reserves $(view $POOL -- get_reserve_list)"
verify() {
    local name=$1 addr=$2 json=$3 i=$4
    view $POOL -- get_reserve --asset $addr | python3 -c '
import json,sys
want=json.loads(sys.argv[2]); got=json.load(sys.stdin)["config"]
bad=[k for k in want if str(got.get(k))!=str(want[k])]
print(f"{sys.argv[1]:8} " + ("config matches" if not bad else "MISMATCH " + ", ".join(f"{k}: {got.get(k)} != {want[k]}" for k in bad)))
' $name "$json"
}
each verify
echo
echo "Next: step 3 of ../pool-deploy.txt."
