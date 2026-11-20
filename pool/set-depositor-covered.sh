#!/bin/bash
# Allowlist (or remove) a Blent Covered Pool backstop depositor.
#
#   ./set-depositor-covered.sh <G... or C...> true|false
#
# Only the fund multisig can do this.  The fund is the transaction source,
# so its 2-of-3 classic signers authorize it by signing the envelope (no
# separate Soroban auth entries).  This script builds and simulates the
# transaction and writes it to set-depositor-<addr>.xdr; then:
#
#   stellar tx sign --sign-with-key <signer 1> < x.xdr > x1.xdr
#   stellar tx sign --sign-with-key <signer 2> < x1.xdr > x2.xdr
#   stellar tx send --network mainnet < x2.xdr
#
# (or import the XDR into Stellar Lab / a wallet for each signer).
# The fund pays the fee, so it needs a little XLM.
#
# Removing a depositor lets anyone force_queue_withdrawal their backstop
# shares.

set -e
cd "$(dirname "$0")"

FUND=GDA5JJFUAGFBNT4BMEGASY7EWBJFOWL2VBXMYY6QKCEOZMXHX6BBXYOB
CONTROLLER=CDAXZS3UGQNWNVKEDZZI5A6L2JN7QRNL7ZAZ436LCRF3IEA3JBPW77PF

USER=$1
ALLOWED=$2
case "$ALLOWED" in true|false) ;; *)
    echo "usage: $0 <address> true|false"; exit 1 ;;
esac
[ -n "$USER" ] || { echo "usage: $0 <address> true|false"; exit 1; }

CUR=$(stellar contract invoke --source-account $FUND --network mainnet --send no \
    --id $CONTROLLER -- is_backstop_depositor --user $USER | tail -1)
echo "$USER currently allowlisted: $CUR"
[ "$CUR" != "$ALLOWED" ] || { echo "nothing to do"; exit 0; }

OUT=set-depositor-$USER-$ALLOWED.xdr
stellar contract invoke --source-account $FUND --network mainnet --build-only \
    --inclusion-fee 1000000 --id $CONTROLLER -- \
    set_backstop_depositor --user $USER --allowed $ALLOWED \
  | stellar tx simulate --network mainnet --source-account $FUND > $OUT
echo "wrote $OUT (simulated, unsigned).  Needs 2 of the fund's 3 signatures."
