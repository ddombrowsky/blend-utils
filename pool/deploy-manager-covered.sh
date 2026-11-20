#!/bin/bash
# Deploy the Blent Covered Pool's admin contract: pool-status-manager
# v0.1.0, owner = the fund multisig, operator = the keeper key on
# the cron host.  See cover-reserve.txt ("Operator key compromise ...").
#
# Deploys the wasm from the GitHub release of
# BLNT-Protocol/pool-status-admin (manager/, verified build, SEP-0055),
# never a local build.
#
# Fixed salt, so the address is known in advance:
#   CCP7DMV4WCVPH2C6ZETXCBFXDPQRLN27CQEAHVILEFWUM7QCG6DMIVDQ
# propose-admin-covered.sh proposes this address as the pool admin.
#
# Checks the release wasm (hash, metadata, attestation), the fund's
# signers and the operator account, asks, then uploads + deploys and reads
# the owner and operator back.

set -eo pipefail
cd "$(dirname "$0")"

SOURCE=xbull                     # pays fees only; no role in the manager
FUND=GDA5JJFUAGFBNT4BMEGASY7EWBJFOWL2VBXMYY6QKCEOZMXHX6BBXYOB
OPERATOR=GAF6YOV7NXCTGR6U2CKZURLD5I7EB4AL5HLVYI3E3VR3C5A2FAY7LT43
SALT=accf1ba4d0e423d6c90943a2db75162d3103497b9c95e86236cf8cd929246242
EXPECTED=CCP7DMV4WCVPH2C6ZETXCBFXDPQRLN27CQEAHVILEFWUM7QCG6DMIVDQ

REPO=BLNT-Protocol/pool-status-admin
RELEASE=manager-v0.1.0_manager_pool-status-manager_pkg0.1.0_cli27.0.0
TAG_REF=refs/tags/manager-v0.1.0
COMMIT=6e5130a42737582cd3586ebffbd2ef4953917edd
SIGNER=stellar-expert/soroban-build-workflow/.github/workflows/release.yml
WASM=release/pool-status-manager_v0.1.0.wasm
WASM_SHA256=db025cf4badff632cae84c30328b3671057179895537ad94973c41038eb8b86a
HORIZON=https://horizon.stellar.org

die() { echo "*** $*; stopping"; exit 1; }

echo "== 1. release wasm"
mkdir -p release
[ -f $WASM ] || gh release download $RELEASE --repo $REPO --dir release
SHA=$(sha256sum $WASM | cut -d' ' -f1)
echo "wasm sha256 $SHA"
[ "$SHA" = "$WASM_SHA256" ] || die "expected $WASM_SHA256"
META=$(stellar contract info meta --wasm $WASM 2>/dev/null)
echo "$META" | grep -E "source_repo|home_domain|rsver|cliver"
echo "$META" | grep -q "source_repo: github:$REPO" || die "source_repo missing"

echo
echo "== 2. attestation"
gh attestation verify $WASM --repo $REPO --signer-workflow $SIGNER \
    --source-ref $TAG_REF --source-digest $COMMIT >/dev/null \
    || die "attestation does not verify"
echo "attested: $REPO @ $COMMIT ($TAG_REF), signed by $SIGNER"

echo
echo "== 3. fund multisig and operator"
curl -sf $HORIZON/accounts/$FUND | python3 -c '
import json, sys
d = json.load(sys.stdin)
t = d["thresholds"]
s = [(x["key"], x["weight"]) for x in d["signers"]]
for k, w in s: print("  fund signer", k, "weight", w)
print("  thresholds", t)
ok = (len(s) == 3 and all(w == 1 for _, w in s)
      and t["low_threshold"] == t["med_threshold"] == t["high_threshold"] == 2)
sys.exit(0 if ok else 1)
' || die "fund is not a clean 2-of-3"
OPXLM=$(curl -sf $HORIZON/accounts/$OPERATOR | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(next(b["balance"] for b in d["balances"] if b["asset_type"] == "native"))
') || die "operator account $OPERATOR not found"
echo "  operator $OPERATOR, XLM $OPXLM"
[ "$OPERATOR" != "$FUND" ] || die "operator must not be the fund"

echo
echo "== 4. address"
ID=$(stellar contract id wasm --salt $SALT --source-account $SOURCE --network mainnet)
echo "manager address will be $ID"
[ "$ID" = "$EXPECTED" ] || die "expected $EXPECTED"
if stellar contract info interface --network mainnet --id $ID >/dev/null 2>&1; then
    die "$ID is already deployed"
fi

echo
echo "owner    $FUND (fund multisig; can never change)"
echo "operator $OPERATOR (keeper; set_status only; owner can replace)"
echo "not upgradeable, no ownership transfer, no renounce."
read -p "Upload and deploy? [y/N] " ok
[ "$ok" = y ] || { echo "stopped; nothing sent"; exit 0; }

echo "== 5. upload + deploy (sends)"
HASH=$(stellar contract upload --source-account $SOURCE --network mainnet --wasm $WASM | tail -1)
echo "wasm hash $HASH"
[ "$HASH" = "$WASM_SHA256" ] || die "uploaded hash differs"
stellar contract deploy --source-account $SOURCE --network mainnet \
    --wasm-hash $HASH --salt $SALT -- --owner $FUND --operator $OPERATOR

echo "== 6. verify"
inv() { stellar contract invoke --source-account $SOURCE --network mainnet --send no --id $ID -- "$@" | tail -1; }
echo "owner:    $(inv get_owner)   (expect \"$FUND\")"
echo "operator: $(inv get_operator)   (expect \"$OPERATOR\")"
echo
echo "Next: ./propose-admin-covered.sh"
