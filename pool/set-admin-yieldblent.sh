#!/bin/bash
# Move the YieldBlent pool admin from xbull (GDJS..) to the multisig
# account GDA5..  Two steps, because the pool requires the new admin to
# accept:
#
#   set-admin-yieldblent.sh propose   xbull signs propose_admin (sends)
#   set-admin-yieldblent.sh build     writes the accept_admin tx (source =
#                                     NEW_ADMIN, simulated) to $XDR
#   set-admin-yieldblent.sh check     prints the current admin
#
# Paste $XDR into Refractor (refractor.space) for the multisig signers;
# it submits once the threshold is met.  accept_admin is authorised by
# the tx source account, so signing the envelope is all that's needed.
#
# The tx has a sequence number and a ledger bound from simulation, so
# rebuild if it sits unsigned for long.

set -e
cd "$(dirname "$0")"

SOURCE=xbull                     # current admin
POOL=CAUTPSQDAJEUV5XEU3EXFVYRGDJLEJGVTFJCFZCSPTDCREAMZ573VF4D       # YieldBlent
NEW_ADMIN=GDA5JJFUAGFBNT4BMEGASY7EWBJFOWL2VBXMYY6QKCEOZMXHX6BBXYOB  # multisig
XDR=${XDR:-accept-admin-yieldblent.xdr}

inv() {
    stellar contract invoke --source-account $SOURCE --network mainnet \
        --inclusion-fee 10000000 --id $POOL "$@"
}
admin() { inv --quiet --send no -- get_admin | tr -d '"'; }

case "$1" in
propose)
    echo "admin now: $(admin)"
    echo "new admin: $NEW_ADMIN"
    inv --send no -- propose_admin --new_admin $NEW_ADMIN >/dev/null
    echo "simulation ok"
    read -p "Send propose_admin as $SOURCE? [y/N] " ok
    [ "$ok" = y ] || { echo "stopped; nothing sent"; exit 0; }
    inv -- propose_admin --new_admin $NEW_ADMIN
    echo "proposed.  Next: $0 build"
    ;;
build)
    stellar contract invoke --source-account $NEW_ADMIN --network mainnet \
        --inclusion-fee 10000000 --id $POOL --build-only -- accept_admin \
        | stellar tx simulate --source-account $NEW_ADMIN --network mainnet \
        > $XDR
    echo "wrote $XDR (source $NEW_ADMIN); submit it to Refractor, then: $0 check"
    ;;
check)
    admin
    ;;
*)
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
