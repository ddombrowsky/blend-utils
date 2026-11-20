#!/bin/bash
# Step 4 of cover-reserve.txt -- the fund deposits 10 USDC into the Blent
# Covered Pool's only backstop tier (FirstLoss = plain USDC).
#
#   ./deposit-backstop-covered.sh [amount in USDC, default 10]
#
# The fund multisig is the depositor, the transaction source and the fee
# payer, so its 2-of-3 classic signers authorize the deposit (and the USDC
# transfer under it) by signing the envelope.  Prints the simulated,
# unsigned transaction XDR on stdout (everything else on stderr):
#
#   ./deposit-backstop-covered.sh | xclip -sel clip
#
# then paste into https://refractor.space; 2 of the fund's 3 signers sign
# and Refractor submits.  The XDR uses the fund's next sequence number, so
# any other fund transaction landing first invalidates it (re-run).
#
# Requires: pool deployed, FUND allowlisted (./add-depositor-covered.sh
# FUND), and FUND holding the deposit plus RESERVE_MIN USDC, because the
# deposit leaves the fund account and the backstop is not covered.
# No reward zone: a Usdc tier earns no BLNT emissions.

set -eo pipefail
cd "$(dirname "$0")"

FUND=GDA5JJFUAGFBNT4BMEGASY7EWBJFOWL2VBXMYY6QKCEOZMXHX6BBXYOB
CONTROLLER=CDAXZS3UGQNWNVKEDZZI5A6L2JN7QRNL7ZAZ436LCRF3IEA3JBPW77PF
POOL=CCH3BNZWTTBB2AKX6NT5OGKQSWP4UNBIKRTRMRDKKJLPMFKULHQZC3XD
BACKSTOP=CAHCUKBPTW5DR5RNXOHCTJD5U76A6EEZXYZAQFRQEEQRXQ3CRUZ6Z3MO
USDC=CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75
TIER=FirstLoss
RESERVE_MIN=90                   # USDC the fund must keep after depositing
FEE=1000000                      # inclusion fee, stroops (0.1 XLM max)

log() { echo "$@" >&2; }
die() { log "*** $*"; exit 1; }

USDC_AMT=${1:-10}
[[ "$USDC_AMT" =~ ^[0-9]+(\.[0-9]{1,7})?$ ]] || die "usage: $0 [amount in USDC]"
AMOUNT=$(python3 -c "from decimal import Decimal as D; print(int(D('$USDC_AMT') * 10**7))")
[ "$AMOUNT" -gt 0 ] || die "amount must be > 0"

view() {
    stellar contract invoke --source-account $FUND --network mainnet --send no \
        --id "$@" 2>/dev/null | tail -1 || true
}

log "== checks"
[ "$(view $CONTROLLER -- is_backstop_depositor --user $FUND)" = true ] \
    || die "FUND is not an allowlisted backstop depositor; run ./add-depositor-covered.sh $FUND first"
log "FUND allowlisted on controller"

S=$(view $BACKSTOP -- user_balance --tier $TIER --pool $POOL --user $FUND \
    | python3 -c 'import json,sys;print(json.load(sys.stdin)["shares"])' 2>/dev/null) \
    || die "can't read backstop balance (pool not deployed yet?)"
log "FUND $TIER shares: $S"
[ "$S" = 0 ] || die "FUND already has backstop shares; nothing to do"

BAL=$(view $USDC -- balance --id $FUND | tr -d '"')
[[ "$BAL" =~ ^[0-9]+$ ]] || die "can't read FUND USDC balance (no trustline?)"
python3 - "$BAL" "$AMOUNT" "$RESERVE_MIN" <<'EOF' >&2 || die "fund would fall below the reserve minimum"
import sys
bal, amt, minimum = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]) * 10**7
print(f"FUND USDC {bal/1e7:.7f}; after deposit {(bal-amt)/1e7:.7f} (min {minimum/1e7:.0f})")
sys.exit(0 if bal - amt >= minimum else 1)
EOF

log
log "== build + simulate"
XDR=$(stellar contract invoke --source-account $FUND --network mainnet --build-only \
        --inclusion-fee $FEE --id $BACKSTOP -- \
        deposit --tier $TIER --from $FUND --pool_address $POOL --amount $AMOUNT \
      | stellar tx simulate --network mainnet --source-account $FUND) \
    || die "build/simulate failed"

log "deposit $USDC_AMT USDC into $TIER of $POOL from FUND"
log "source/fee payer $FUND; needs 2 of its 3 signatures"
log "paste into Refractor:"
echo "$XDR"
log
log "After it lands: site + cover terms published, then ./go-live-covered.sh"
