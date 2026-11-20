#!/bin/bash
# Step 3 of cover-reserve.txt -- add the USDC trustline to the Blent Cover
# Reserve Fund multisig, for signing in Refractor.
#
#   ./add-trustline-covered.sh
#
# Prints the unsigned transaction XDR on stdout (everything else on
# stderr):
#
#   ./add-trustline-covered.sh | xclip -sel clip
#
# then paste into https://refractor.space; 2 of the fund's 3 signers sign
# and Refractor submits.  The fund is the source and pays the fee.  The
# XDR uses the fund's next sequence number, so any other fund transaction
# landing first invalidates it (re-run).
#
# USDC is Circle's (the pool's USDC SAC, CCW67...MI75, wraps this asset);
# the script checks that against the SAC before building.  The trustline
# locks another 0.5 XLM of the fund's minimum balance.
#
# After it lands: send the fund 100 USDC (90 reserve + 10 backstop), then
# ./deposit-backstop-covered.sh.

set -eo pipefail
cd "$(dirname "$0")"

FUND=GDA5JJFUAGFBNT4BMEGASY7EWBJFOWL2VBXMYY6QKCEOZMXHX6BBXYOB
USDC_ISSUER=GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN
USDC_SAC=CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75
HORIZON=https://horizon.stellar.org
FEE=100000                       # stroops (0.01 XLM); classic op, no Soroban fee

log() { echo "$@" >&2; }
die() { log "*** $*"; exit 1; }

[ $# -eq 0 ] || die "usage: $0   (no arguments)"

SAC_NAME=$(stellar contract invoke --source-account $FUND --network mainnet --send no \
    --id $USDC_SAC -- name 2>/dev/null | tail -1 | tr -d '"') || true
[ "$SAC_NAME" = "USDC:$USDC_ISSUER" ] \
    || die "pool USDC SAC is '$SAC_NAME', expected USDC:$USDC_ISSUER"

ACCT=$(curl -sf $HORIZON/accounts/$FUND) || die "could not load fund account"

python3 -c '
import json, sys
d = json.loads(sys.argv[1]); issuer = sys.argv[2]
t = d["thresholds"]
s = [(x["key"], x["weight"]) for x in d["signers"]]
ok = (len(s) == 3 and all(w == 1 for _, w in s)
      and t["low_threshold"] == t["med_threshold"] == t["high_threshold"] == 2)
if not ok:
    print("*** fund is not a clean 2-of-3:", s, t, file=sys.stderr); sys.exit(1)
if any(b.get("asset_code") == "USDC" and b.get("asset_issuer") == issuer
       for b in d["balances"]):
    print("*** fund already has the USDC trustline; nothing to do", file=sys.stderr)
    sys.exit(1)
xlm = float(next(b["balance"] for b in d["balances"] if b["asset_type"] == "native"))
entries = 2 + d["subentry_count"] + 1 + d.get("num_sponsoring", 0) - d.get("num_sponsored", 0)
need = entries * 0.5 + 0.01
print(f"fund 2-of-3 ok; XLM {xlm:.7f}, needs {need:.2f} after trustline", file=sys.stderr)
sys.exit(0 if xlm >= need else 1)
' "$ACCT" $USDC_ISSUER || die "checks failed"

XDR=$(stellar tx new change-trust --source-account $FUND --network mainnet \
        --build-only --inclusion-fee $FEE --line USDC:$USDC_ISSUER) \
    || die "build failed"

log "change_trust USDC:$USDC_ISSUER (max limit) on $FUND"
log "needs 2 of the fund's 3 signatures"
log "paste into Refractor:"
echo "$XDR"
