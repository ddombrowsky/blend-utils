#!/bin/bash
# Build the transaction that allowlists a Blent Covered Pool backstop
# depositor on the access controller, for signing in Refractor.
#
#   ./add-depositor-covered.sh <G... or C... address>
#
# Prints the simulated, unsigned transaction XDR on stdout (everything
# else goes to stderr), so
#
#   ./add-depositor-covered.sh G... | xclip -sel clip
#
# puts it straight on the clipboard.  Paste it into
# https://refractor.space, then 2 of the fund's 3 signers sign there;
# Refractor submits once the threshold is met.
#
# The fund multisig is the transaction source and pays the fee, so its
# classic signers authorize set_backstop_depositor by signing the envelope.
# The XDR uses the fund's next sequence number: any other fund transaction
# that lands first invalidates it (just re-run this script).
#
# To remove a depositor, use ./set-depositor-covered.sh <addr> false.

set -eo pipefail
cd "$(dirname "$0")"

FUND=GDA5JJFUAGFBNT4BMEGASY7EWBJFOWL2VBXMYY6QKCEOZMXHX6BBXYOB
CONTROLLER=CDAXZS3UGQNWNVKEDZZI5A6L2JN7QRNL7ZAZ436LCRF3IEA3JBPW77PF
HORIZON=https://horizon.stellar.org
FEE=1000000                      # inclusion fee, stroops (0.1 XLM max)

log() { echo "$@" >&2; }
die() { log "*** $*"; exit 1; }

USER=$1
[ $# -eq 1 ] || die "usage: $0 <G... or C... address>"
[[ "$USER" =~ ^[GC][A-Z2-7]{55}$ ]] || die "$USER is not a G... or C... address"

inv() {
    stellar contract invoke --source-account $FUND --network mainnet --send no \
        --id $CONTROLLER -- "$@" 2>/dev/null | tail -1 || true
}

ADMIN=$(inv admin | tr -d '"')
[ "$ADMIN" = "$FUND" ] || die "controller admin is '$ADMIN', expected $FUND"

CUR=$(inv is_backstop_depositor --user $USER)
[ -n "$CUR" ] || die "could not read controller (bad address checksum?)"
[ "$CUR" = false ] || die "$USER is already allowlisted; nothing to do"

XLM=$(curl -sf $HORIZON/accounts/$FUND | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(next(b["balance"] for b in d["balances"] if b["asset_type"] == "native"))
') || die "could not load fund account"
log "fund XLM balance: $XLM"

XDR=$(stellar contract invoke --source-account $FUND --network mainnet --build-only \
        --inclusion-fee $FEE --id $CONTROLLER -- \
        set_backstop_depositor --user $USER --allowed true \
      | stellar tx simulate --network mainnet --source-account $FUND) \
    || die "build/simulate failed"

log "set_backstop_depositor $USER true"
log "source/fee payer $FUND; needs 2 of its 3 signatures"
log "paste into Refractor:"
echo "$XDR"
