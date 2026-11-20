#!/bin/bash
# Step 1 of cover-reserve.txt: deploy the Blent Covered Pool from the BLNT
# v3 pool factory.
#
# The salt is fixed, so the pool address is known in advance and a second
# run can't create a second pool (the factory rejects a reused salt).
# Simulated 2026-11-17 -> CCH3BNZWTTBB2AKX6NT5OGKQSWP4UNBIKRTRMRDKKJLPMFKULHQZC3XD
# (the address depends only on the salt).
# Abandoned: CDL3VILEP75UJCR5DK4BFLOUYSRFRHYRFSEWRGKDV366UH4QOCFA2GNN,
# deployed 2026-11-17 as "Blent Covered Pool", which the UI shows as
# "Blent Covered Pool Pool".  The name is immutable.  Left in setup.
#
# Simulates first, asks before sending, then reads the new pool back.

set -e
cd "$(dirname "$0")"

SOURCE=xbull                     # signs, pays fees, and becomes pool admin
                                 # (movable later: propose_admin/accept_admin)
ADMIN=$(stellar keys address $SOURCE)
FACTORY=CAKLFWAHB2RIYRBSPUL6EH43AIQ5ILBEM7HTMWYSJRL7PHZQ676KMCV5
ORACLE=CDN7JD6SP32RZHB3DHK4S4AWCCQF6GYIUO455UCR4RGRZILZDRD24N36
NAME="Blent Covered"                # the UI appends " Pool"
SALT=d22c70300b67adf34402e7b7490a4d3ef82b004b8b3dce846f3fd93a18f85bfe
EXPECTED=CCH3BNZWTTBB2AKX6NT5OGKQSWP4UNBIKRTRMRDKKJLPMFKULHQZC3XD

# One plain-USDC FirstLoss tier (no BLNT emissions).  backstop_config is
# IMMUTABLE.
TAKE_RATE=5000000                # 50% of interest to the backstop
MAX_POSITIONS=4                  # 3 reserves + 1 spare
MIN_COLLATERAL=50000000          # $5 (USDC base, 7 decimals)
BACKSTOP_CONFIG='[{"asset":"Usdc","take_rate_weight":1}]'
# Access controller (backstop allowlist, admin = fund multisig), from
# deploy-controller-covered.sh.  IMMUTABLE once the pool is deployed.
CONTROLLER=CDAXZS3UGQNWNVKEDZZI5A6L2JN7QRNL7ZAZ436LCRF3IEA3JBPW77PF
FUND=GDA5JJFUAGFBNT4BMEGASY7EWBJFOWL2VBXMYY6QKCEOZMXHX6BBXYOB

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
        --backstop_config "$BACKSTOP_CONFIG" \
        --access_controller "\"$CONTROLLER\""
}

echo "== 0. oracle check (every reserve needs a price)"
../oracle/deploy-aggregator.sh check $ORACLE

echo
echo "== 0b. controller check (must be deployed, admin = fund)"
CADMIN=$(inv --send no --id $CONTROLLER -- admin 2>/dev/null | tail -1 | tr -d '"') || true
if [ "$CADMIN" != "$FUND" ]; then
    echo "*** controller $CONTROLLER not deployed or admin '$CADMIN' != $FUND"
    echo "    run ./deploy-controller-covered.sh first"
    exit 1
fi
echo "controller $CONTROLLER, admin $CADMIN"

echo
echo "== 1. simulate deploy"
echo "admin $ADMIN ($SOURCE)"
echo "name $NAME, oracle $ORACLE"
echo "take rate $TAKE_RATE, max_positions $MAX_POSITIONS, min_collateral $MIN_COLLATERAL"
echo "backstop $BACKSTOP_CONFIG"
echo "access_controller $CONTROLLER"
SIM=$(deploy --send no | tail -1 | tr -d '"')
echo "pool address would be $SIM"
if [ "$SIM" != "$EXPECTED" ]; then
    echo "*** expected $EXPECTED; stopping"
    exit 1
fi

echo
read -p "backstop_config, oracle and access_controller can't be changed later.  Deploy? [y/N] " ok
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
echo "Expect status 6 (setup).  Next: ./set-reserves-covered.sh"
