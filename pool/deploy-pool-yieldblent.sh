#!/bin/bash
# One-off: step 1 of ../pool-deploy.txt -- deploy the YieldBlent pool from
# the BLNT v3 pool factory.  Not tracked (*.local.sh).  Delete when done.
#
# The salt is fixed, so the pool address is known in advance and a second
# run can't create a second pool (the factory rejects a reused salt).
#
# Simulates first, asks before sending, then reads the new pool back.

set -e
cd "$(dirname "$0")"

SOURCE=xbull                     # signs, pays fees, and becomes pool admin
                                 # (movable later: propose_admin/accept_admin)
ADMIN=$(stellar keys address $SOURCE)
FACTORY=CAKLFWAHB2RIYRBSPUL6EH43AIQ5ILBEM7HTMWYSJRL7PHZQ676KMCV5
ORACLE=CDN7JD6SP32RZHB3DHK4S4AWCCQF6GYIUO455UCR4RGRZILZDRD24N36
NAME=YieldBlent
SALT=6f3fa7b6ab973e2fe922fba039ad3c24db5c44b546ffc60bab54a32f4af6191e
EXPECTED=CAUTPSQDAJEUV5XEU3EXFVYRGDJLEJGVTFJCFZCSPTDCREAMZ573VF4D

# Same as the existing BLNT v3 pool, minus its Usdc tier.  backstop_config
# is IMMUTABLE.
TAKE_RATE=2000000                # 20% of interest to the backstop
MAX_POSITIONS=6
MIN_COLLATERAL=50000000          # $5 (USDC base, 7 decimals)
BACKSTOP_CONFIG='[{"asset":"BlntXlm","take_rate_weight":4},{"asset":"BlntUsdc","take_rate_weight":3}]'
# access_controller omitted = None = permissionless

inv() {
    stellar contract invoke --source-account $SOURCE --network mainnet \
        --inclusion-fee 10000000 "$@"
}

deploy() {
    inv "$@" --id $FACTORY -- deploy \
        --admin $ADMIN \
        --name "$NAME" \
        --salt $SALT \
        --oracle $ORACLE \
        --backstop_take_rate $TAKE_RATE \
        --max_positions $MAX_POSITIONS \
        --min_collateral $MIN_COLLATERAL \
        --backstop_config "$BACKSTOP_CONFIG"
}

echo "== 0. oracle check (every reserve needs a price)"
../oracle/deploy-aggregator.sh check $ORACLE

echo
echo "== 1. simulate deploy"
echo "admin $ADMIN ($SOURCE)"
echo "name $NAME, oracle $ORACLE"
echo "take rate $TAKE_RATE, max_positions $MAX_POSITIONS, min_collateral $MIN_COLLATERAL"
echo "backstop $BACKSTOP_CONFIG"
SIM=$(deploy --send no | tail -1 | tr -d '"')
echo "pool address would be $SIM"
if [ "$SIM" != "$EXPECTED" ]; then
    echo "*** expected $EXPECTED; stopping"
    exit 1
fi

echo
read -p "backstop_config and oracle can't be changed later.  Deploy? [y/N] " ok
[ "$ok" = y ] || { echo "stopped; nothing sent"; exit 0; }

echo "== 2. deploy (sends)"
POOL=$(deploy --send yes | tail -1 | tr -d '"')
echo "POOL=$POOL"

echo "== 3. verify"
echo "is_pool:   $(inv --send no --id $FACTORY -- is_pool --pool_address $POOL | tail -1)"
echo "backstop:  $(inv --send no --id $FACTORY -- backstop_config --pool_address $POOL | tail -1)"
echo "config:    $(inv --send no --id $POOL -- get_config | tail -1)"
echo "admin:     $(inv --send no --id $POOL -- get_admin | tail -1)"
echo
echo "Expect status 6 (setup).  Record POOL=$POOL in yieldblent.txt and"
echo "pool-deploy.txt, then step 2 (reserves)."
