#!/bin/bash
# xbull (the current pool admin) proposes the pool-status-manager as the
# admin of the Blent Covered Pool.  The pool admin does not change until
# the fund multisig accepts through the manager (accept_admin, a Refractor
# XDR with the fund as source; build it only once no other fund
# transaction is pending, or the sequence numbers collide).
#
# The pool keeps the proposal for 10 days; re-run to propose again.
#
# Checks the manager (deployed, owner = fund, operator = keeper) and the
# pool admin, simulates, asks, sends, and reads the proposal back.

set -eo pipefail
cd "$(dirname "$0")"

SOURCE=xbull                     # current pool admin
POOL=CCH3BNZWTTBB2AKX6NT5OGKQSWP4UNBIKRTRMRDKKJLPMFKULHQZC3XD
MANAGER=CCP7DMV4WCVPH2C6ZETXCBFXDPQRLN27CQEAHVILEFWUM7QCG6DMIVDQ
FUND=GDA5JJFUAGFBNT4BMEGASY7EWBJFOWL2VBXMYY6QKCEOZMXHX6BBXYOB
OPERATOR=GAF6YOV7NXCTGR6U2CKZURLD5I7EB4AL5HLVYI3E3VR3C5A2FAY7LT43
WASM_SHA256=db025cf4badff632cae84c30328b3671057179895537ad94973c41038eb8b86a

die() { echo "*** $*; stopping"; exit 1; }
inv() {
    stellar contract invoke --source-account $SOURCE --network mainnet \
        --inclusion-fee 10000000 "$@"
}
view() { inv --send no --id "$@" 2>/dev/null | tail -1 | tr -d '"' || true; }

ADMIN=$(stellar keys address $SOURCE)

echo "== 1. manager"
stellar contract info meta --network mainnet --id $MANAGER >/dev/null 2>&1 \
    || die "manager $MANAGER is not deployed; run ./deploy-manager-covered.sh"
stellar contract fetch --network mainnet --id $MANAGER -o /tmp/mgr.$$ 2>/dev/null \
    || die "can't fetch manager code"
GOT=$(sha256sum /tmp/mgr.$$ | cut -d' ' -f1); rm -f /tmp/mgr.$$
[ "$GOT" = "$WASM_SHA256" ] || die "manager code is $GOT, expected $WASM_SHA256"
O=$(view $MANAGER -- get_owner); P=$(view $MANAGER -- get_operator)
echo "manager $MANAGER: code $GOT"
echo "  owner $O"; echo "  operator $P"
[ "$O" = "$FUND" ] || die "owner is not the fund"
[ "$P" = "$OPERATOR" ] || die "operator is not the keeper key"

echo
echo "== 2. pool"
CUR=$(view $POOL -- get_admin)
echo "pool $POOL admin $CUR"
[ "$CUR" = "$ADMIN" ] || die "pool admin is not $SOURCE ($ADMIN)"

echo
echo "== 3. simulate propose_admin"
inv --send no --id $POOL -- propose_admin --new_admin $MANAGER >/dev/null 2>/tmp/pa.$$ \
    || { cat /tmp/pa.$$; rm -f /tmp/pa.$$; die "simulation failed"; }
rm -f /tmp/pa.$$
echo "simulation ok"

echo
read -p "Propose $MANAGER as admin of $POOL? [y/N] " ok
[ "$ok" = y ] || { echo "stopped; nothing sent"; exit 0; }

echo "== 4. propose_admin (sends)"
inv --send yes --id $POOL -- propose_admin --new_admin $MANAGER

echo "== 5. verify"
stellar contract read --network mainnet --id $POOL --durability temporary \
    --key PropAdmin 2>/dev/null | tail -1 || echo "(couldn't read PropAdmin; check on stellar.expert)"
echo "pool admin still: $(view $POOL -- get_admin)  (changes on accept)"
echo
echo "Next: once no other fund transaction is pending, build the fund's"
echo "accept_admin XDR (manager accept_admin --pool $POOL) for Refractor."
