#!/bin/bash
# One-off: step 3 of ../pool-deploy.txt -- set the YieldBlent pool's BLNT
# emissions split.  Not tracked (*.local.sh).  Delete when done.
#
# Shares are relative weights (each is divided by the total of the
# enabled shares); these add up to 1.0.  set_emissions_config replaces
# the whole config, so re-running with the same list is harmless.
#
# This only decides how the pool splits BLNT it receives.  The pool
# receives none until it is in the backstop reward zone, which needs a
# BLNT LP backstop deposit (step 4) and then backstop add_reward.

set -e
cd "$(dirname "$0")"

SOURCE=xbull                     # pool admin
POOL=CAUTPSQDAJEUV5XEU3EXFVYRGDJLEJGVTFJCFZCSPTDCREAMZ573VF4D

# res_type 0 = borrowers (dTokens), 1 = suppliers (bTokens)
# reserve token id = res_index * 2 + res_type
EMISSIONS='[
  {"res_index":1,"res_type":0,"share":3000000},
  {"res_index":0,"res_type":1,"share":2000000},
  {"res_index":9,"res_type":1,"share":1500000},
  {"res_index":2,"res_type":0,"share":1500000},
  {"res_index":7,"res_type":1,"share":1000000},
  {"res_index":8,"res_type":1,"share":1000000}
]'
# what the stored map should look like afterward (token id -> share)
EXPECTED='{"1":2000000,"2":3000000,"4":1500000,"15":1000000,"17":1000000,"19":1500000}'

inv() {
    stellar contract invoke --source-account $SOURCE --network mainnet \
        --inclusion-fee 10000000 "$@"
}
stored() {
    stellar contract read --network mainnet --id $POOL --key PoolEmis \
        --durability persistent --output string 2>&1 | tail -1
}

echo "== 0. pool state"
LIST=$(inv --send no --id $POOL -- get_reserve_list | tail -1)
echo "$LIST" | python3 -c '
import json,sys
names=["XLM","USDC","EURC","AQUA","USDGLO","USTRY","CETES","PYUSD","USDT0","SolvBTC"]
l=json.load(sys.stdin)
print(f"{len(l)} reserves")
for i,a in enumerate(l): print("  %d %-8s %s" % (i, names[i] if i < len(names) else "?", a))
'
CUR=$(stored)
case "$CUR" in PoolEmis,*) ;; *) CUR="(none)";; esac
echo "current emissions config: $CUR"

echo
echo "== 1. planned split"
echo "  USDC    borrow  30%   (token id 2)"
echo "  XLM     supply  20%   (token id 1)"
echo "  SolvBTC supply  15%   (token id 19)"
echo "  EURC    borrow  15%   (token id 4)"
echo "  PYUSD   supply  10%   (token id 15)"
echo "  USDT0   supply  10%   (token id 17)"
inv --send no --id $POOL -- set_emissions_config \
    --res_emission_metadata "$EMISSIONS" > /dev/null
echo "simulation ok"

echo
read -p "Set this emissions config on $POOL? [y/N] " ok
[ "$ok" = y ] || { echo "stopped; nothing sent"; exit 0; }

echo "== 2. set_emissions_config (sends)"
inv --send yes --id $POOL -- set_emissions_config \
    --res_emission_metadata "$EMISSIONS"

echo "== 3. verify"
GOT=$(stored)
echo "stored: $GOT"
python3 -c '
import csv,json,sys
row=next(csv.reader([sys.argv[1]]))   # PoolEmis,"{...}",ttl,ttl (CSV)
got=json.loads(row[1])
want=json.loads(sys.argv[2])
print("matches" if {k:int(v) for k,v in got.items()}==want else f"*** MISMATCH, expected {want}")
' "$GOT" "$EXPECTED"
echo
echo "Next: step 4 (BLNT LP backstop deposit), then backstop add_reward."
