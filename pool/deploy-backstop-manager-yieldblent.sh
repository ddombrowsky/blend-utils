#!/bin/bash
# Deploy a backstop manager (BLNT-Protocol/backstop-manager v1.0.1) on
# mainnet for the YieldBlent pool's BLNT v3 backstop position.
#
#   owner:   xbull   (owns the funds; can do everything, incl. set_manager,
#                     set_harvest_bps, transfer_token)
#   manager: claudio, scope 0 = Low (b_claim, harvest)
#
# The salt is fixed, so the address is known in advance and a second run
# can't create a second instance.  Asks before sending, then reads it back.
#
# Manage it afterwards with the backstop-manager CLI:
#   CONFIG=$PWD/backstop-manager-yieldblent.env ../../backstop-manager/cli/manager.sh
# (signs as claudio; prefix SOURCE=xbull for owner/high-scope operations)

set -e
cd "$(dirname "$0")"

SOURCE=xbull                     # signs, pays fees, becomes owner
OWNER=$(stellar keys address $SOURCE)
MANAGER=$(stellar keys address claudio)
SCOPE=0                          # 0 Low, 1 Medium, 2 High

# Release v1.0.1 (tag commit 5c47084), StellarExpert attested build;
# already installed on mainnet.
WASM_HASH=3c7e6757681b4bead581f0772637a6e834d6007e69b0a51d198075db41112269
SALT=64f0527664d61102bf4aedd92c3c4c66dd0f4f04ec36d6f1250e6e00f764f2c2
EXPECTED=CA7AO4OH5XVSVLGMWREBGASI3TQ4GIYAZGN6E5P3RLOENRRSCWX27TFE

BACKSTOP=CAHCUKBPTW5DR5RNXOHCTJD5U76A6EEZXYZAQFRQEEQRXQ3CRUZ6Z3MO   # BLNT v3
POOL=CAUTPSQDAJEUV5XEU3EXFVYRGDJLEJGVTFJCFZCSPTDCREAMZ573VF4D       # YieldBlent

view() {
    stellar contract invoke --quiet --send=no --source-account $SOURCE \
        --network mainnet --id "$ID" -- "$@"
}

echo "== 1. check"
echo "owner    $OWNER ($SOURCE)"
echo "manager  $MANAGER (claudio), scope $SCOPE"
echo "wasm     $WASM_HASH"
echo "backstop $BACKSTOP"
echo "pool     $POOL"
ID=$(stellar contract id wasm --salt $SALT --source-account $SOURCE --network mainnet)
echo "address  $ID"
if [ "$ID" != "$EXPECTED" ]; then
    echo "*** expected $EXPECTED; stopping"
    exit 1
fi
if view owner >/dev/null 2>&1; then
    echo "already deployed:"
else
    echo
    read -p "Deploy? [y/N] " ok
    [ "$ok" = y ] || { echo "stopped; nothing sent"; exit 0; }

    echo "== 2. deploy (sends)"
    stellar contract deploy --source-account $SOURCE --network mainnet \
        --wasm-hash $WASM_HASH --salt $SALT -- \
        --owner $OWNER \
        --manager $MANAGER \
        --admin_scope $SCOPE \
        --backstops "[\"$BACKSTOP\"]" \
        --pools "[\"$POOL\"]"
fi

echo "== 3. verify"
echo "owner:       $(view owner)"
echo "manager:     $(view manager)"
echo "backstops:   $(view backstops)"
echo "pools:       $(view pools)"
echo "harvest_bps: $(view harvest_bps)"
