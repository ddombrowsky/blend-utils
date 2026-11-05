#!/bin/bash

# Deploy an oracle aggregator for the BLNT v3 ybx-style pool (see
# ../pool-deploy.txt).  Base is USDC; every other asset is priced by the
# Reflector Stellar DEX feed.  No base-like (pinned 1.0) assets.
#
# Contract is blend-capital/oracle-aggregator v2.0.0, already installed on
# mainnet (same wasm as the BLNT oracle CCVTVW2C...POATS).  README:
#   ~/work/script3/blend/oracle-aggregator, `git show v2.0.0:README.md`
#
# Assets can NEVER be removed or edited once added, so `add-assets` only
# simulates unless SEND=yes.  New assets can be added at any time; both
# add-oracle and add-assets skip what's already configured, so re-running
# them is safe.  add_asset returns the price it would report,
# so the simulation shows whether Reflector has a price for each asset.
#
# usage:
#   ./deploy-aggregator.sh deploy                   # prints the new contract id
#   ./deploy-aggregator.sh add-oracle <id>          # sends add_oracle(Reflector)
#   ./deploy-aggregator.sh add-assets <id>          # simulate add_asset for each
#   SEND=yes ./deploy-aggregator.sh add-assets <id> # really send them
#   ./deploy-aggregator.sh check <id>               # config + lastprice for all

set -e

NETWORK=mainnet
SOURCE=xbull
ADMIN=$(stellar keys address $SOURCE)

# blend-capital/oracle-aggregator v2.0.0_oracle-aggregator_cli22.0.1
WASM_HASH=41df04894bf2d8291492326f7a6ab9c90a90cc9828e31990ce8aeeab42680bfd

# Reflector Stellar DEX feed: base USDC, 14 decimals, 300s resolution.
# The aggregator's base must match it.
REFLECTOR=CALI2BYU2JE6WVRUFYTS6MSBNEHGJ35P4AVCZYF3B6QOE3QKOB2PLE6M
USDC=CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75

DECIMALS=7
MAX_AGE=900     # seconds, 360..3600 (ybx uses 900)

# name contract max_dev
# max_dev = max % change between two consecutive Reflector rounds (5 min),
# else lastprice returns None and the pool can't price that asset.  0
# disables the check.  It only compares consecutive rounds, so a price held
# for two rounds passes; a small max_dev forces a manipulation to ramp up
# slowly instead (2% steps: ~21 rounds to reach 1.5x).  Downside: a real
# move bigger than max_dev (e.g. a stablecoin depeg) makes the asset
# unpriceable until it settles.  See "Thin-market collateral" in
# ../pool-deploy.txt.
ASSETS="
XLM    CAS3J7GYLGXMF6TDJBBYYSE3HQ6BBSMLNUQ34T6TZMYMW2EVH34XOWMA 0
EURC   CDTKPWPLOURQA2SGTKTUQOWRCBZEORB4BWBOMJ3D3ZTQQSGE5F6JBQLV 10
AQUA   CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK 10
USDGLO CB226ZOEYXTBPD3QEGABTJYSKZVBP2PASEISLG3SBMTN5CE4QZUVZ3CE 2
USTRY  CBLV4ATSIWU67CFSQU2NVRKINQIKUZ2ODSZBUJTJ43VJVRSBTZYOPNUR 2
CETES  CAL6ER2TI6CTRAY6BFXWNWA7WTYXUXTQCHUBCIBU5O6KM3HJFG6Z6VXV 3
PYUSD  CCCRWH6Q3FNP3I2I57BDLM5AFAT7O6OF6GKQOC6SSJNDAVRZ57SPHGU2 2
USDT0  CBSJZEIO5C7KC2SF3MKSNXXJSW5G3VTNBX4ATMKUI3B2MR4JKM4R26YF 2
SolvBTC CBIJBDNZNF4X35BJ4FFZWCDBSCKOP5NB4PLG4SNENRMLAPYG4P5FM6VN 10"

if [ "$SEND" = yes ]; then SENDOPT="--send yes"; else SENDOPT="--send no"; fi

inv() {
    id=$1; shift
    stellar contract invoke --id $id --source-account $SOURCE \
        --network $NETWORK --inclusion-fee 10000000 $SENDOPT -- "$@"
}

case "$1" in
deploy)
    stellar contract deploy --wasm-hash $WASM_HASH \
        --source-account $SOURCE --network $NETWORK --inclusion-fee 10000000 -- \
        --admin $ADMIN \
        --base "{\"Stellar\":\"$USDC\"}" \
        --decimals $DECIMALS \
        --max_age $MAX_AGE
    ;;

add-oracle)
    ID=${2:?usage: $0 add-oracle <aggregator id>}
    SENDOPT="--send no"
    if inv $ID oracles | grep -q $REFLECTOR; then
        echo "Reflector already added"
    else
        SENDOPT="--send yes"
        inv $ID add_oracle --oracle_id $REFLECTOR
        SENDOPT="--send no"
    fi
    inv $ID oracles
    ;;

add-assets)
    ID=${2:?usage: $0 add-assets <aggregator id>}
    [ "$SEND" = yes ] || echo "*** simulating only; SEND=yes to send ***"
    CONFIGURED=$(SENDOPT="--send no" inv $ID asset_configs)
    echo "$ASSETS" | while read name addr maxdev; do
        [ -n "$name" ] || continue
        case "$CONFIGURED" in *$addr*)
            echo "skip $name (already added)"; continue;; esac
        echo "add_asset $name max_dev $maxdev"
        inv $ID add_asset \
            --asset "{\"Stellar\":\"$addr\"}" \
            --oracle_id $REFLECTOR \
            --oracle_asset "{\"Stellar\":\"$addr\"}" \
            --max_dev $maxdev
    done
    ;;

check)
    ID=${2:?usage: $0 check <aggregator id>}
    SENDOPT="--send no"
    echo "base $(inv $ID base) decimals $(inv $ID decimals) max_age $(inv $ID max_age)"
    inv $ID oracles
    printf '%-7s ' USDC; inv $ID lastprice --asset "{\"Stellar\":\"$USDC\"}"
    echo "$ASSETS" | while read name addr maxdev; do
        [ -n "$name" ] || continue
        printf '%-7s ' $name
        inv $ID lastprice --asset "{\"Stellar\":\"$addr\"}" 2>&1 | tail -1
    done
    ;;

*)
    sed -n '/^# usage:/,/^$/p' $0
    exit 1
    ;;
esac
