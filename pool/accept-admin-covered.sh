#!/bin/bash
# Step 4e of cover-reserve.txt: the fund multisig accepts the pool admin
# role for the pool-status-manager, for signing in Refractor.
#
#   ./accept-admin-covered.sh | xclip -sel clip
#
# Prints the simulated, unsigned transaction XDR on stdout (everything
# else on stderr); paste it into https://refractor.space, 2 of the fund's
# 3 signers sign, Refractor submits.  The fund is the source and pays the
# fee; its signature authorizes manager.accept_admin (owner only), and the
# manager in turn satisfies the pool's accept_admin auth as the proposed
# admin.  The XDR uses the fund's next sequence number: build it only when
# no other fund transaction is pending.
#
# Requires: ./propose-admin-covered.sh has run and its proposal (10 days)
# has not expired.

set -eo pipefail
cd "$(dirname "$0")"

FUND=GDA5JJFUAGFBNT4BMEGASY7EWBJFOWL2VBXMYY6QKCEOZMXHX6BBXYOB
POOL=CCH3BNZWTTBB2AKX6NT5OGKQSWP4UNBIKRTRMRDKKJLPMFKULHQZC3XD
MANAGER=CCP7DMV4WCVPH2C6ZETXCBFXDPQRLN27CQEAHVILEFWUM7QCG6DMIVDQ
OPERATOR=GAF6YOV7NXCTGR6U2CKZURLD5I7EB4AL5HLVYI3E3VR3C5A2FAY7LT43
FEE=1000000                      # inclusion fee, stroops (0.1 XLM max)

log() { echo "$@" >&2; }
die() { log "*** $*"; exit 1; }

view() {
    stellar contract invoke --source-account $FUND --network mainnet --send no \
        --id "$@" 2>/dev/null | tail -1 | tr -d '"' || true
}

O=$(view $MANAGER -- get_owner); P=$(view $MANAGER -- get_operator)
[ "$O" = "$FUND" ] || die "manager owner is '$O', expected $FUND"
[ "$P" = "$OPERATOR" ] || die "manager operator is '$P', expected $OPERATOR"
log "manager $MANAGER: owner FUND, operator $OPERATOR"

ADMIN=$(view $POOL -- get_admin)
[ "$ADMIN" != "$MANAGER" ] || die "manager is already the pool admin; nothing to do"
log "pool admin now: $ADMIN"

PROP=$(stellar contract read --network mainnet --id $POOL --durability temporary \
    --key PropAdmin 2>/dev/null | tail -1) || true
case "$PROP" in
    *$MANAGER*) log "proposal: $PROP" ;;
    *) die "no live proposal for $MANAGER (got '$PROP'); run ./propose-admin-covered.sh" ;;
esac

XDR=$(stellar contract invoke --source-account $FUND --network mainnet --build-only \
        --inclusion-fee $FEE --id $MANAGER -- accept_admin --pool $POOL \
      | stellar tx simulate --network mainnet --source-account $FUND) \
    || die "build/simulate failed"

log "manager.accept_admin(pool $POOL), source FUND"
log "needs 2 of the fund's 3 signatures"
log "paste into Refractor:"
echo "$XDR"
log
log "After it lands: pool get_admin should be $MANAGER"
