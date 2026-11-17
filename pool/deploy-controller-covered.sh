#!/bin/bash
# Step 0b of cover-reserve.txt: deploy the Blent Covered Pool access
# controller, admin = the fund multisig.
#
# Deploys the wasm from the GitHub release of
# BLNT-Protocol/blnt-covered-backstop-controller (verified build, SEP-0055),
# never a local build: a local build matches no attestation.
#
# Fixed salt, so the address is known in advance:
#   CDAXZS3UGQNWNVKEDZZI5A6L2JN7QRNL7ZAZ436LCRF3IEA3JBPW77PF
# deploy-pool-covered.sh binds this address immutably.
# (CA5QQDOQ...IBY5, deployed 2026-11-14 from a local build without
# source_repo, is abandoned; nothing binds it.)
#
# Downloads the release wasm, checks hash, metadata and attestation, and
# the fund's signers, asks, then uploads + deploys and reads it back.

set -e
cd "$(dirname "$0")"

SOURCE=xbull                     # pays fees only; has no power over the controller
FUND=GDA5JJFUAGFBNT4BMEGASY7EWBJFOWL2VBXMYY6QKCEOZMXHX6BBXYOB
SALT=c5a78d3a5fadba6c8e651f21f7b5903e8b45603e85be35a7ca69f47948b0a9d0
EXPECTED=CDAXZS3UGQNWNVKEDZZI5A6L2JN7QRNL7ZAZ436LCRF3IEA3JBPW77PF

REPO=BLNT-Protocol/blnt-covered-backstop-controller
RELEASE=v1.0.0_blnt-covered-backstop-controller_cli25.1.0
TAG_REF=refs/tags/v1.0.0
COMMIT=c1b87e3d322d5d247a83d0d7b2b14b04464db7cf
SIGNER=stellar-expert/soroban-build-workflow/.github/workflows/release.yml
WASM=release/blnt-covered-backstop-controller_v1.0.0.wasm
WASM_SHA256=9e18c6cc732f3e71df079b52586c7d10870b92df8823d4389ab9ae7a6d885a1b
HORIZON=https://horizon.stellar.org

echo "== 1. release wasm"
mkdir -p release
[ -f $WASM ] || gh release download $RELEASE --repo $REPO --dir release
SHA=$(sha256sum $WASM | cut -d' ' -f1)
echo "wasm sha256 $SHA"
[ "$SHA" = "$WASM_SHA256" ] || { echo "*** expected $WASM_SHA256; stopping"; exit 1; }
META=$(stellar contract info meta --wasm $WASM 2>/dev/null)
echo "$META" | grep -E "source_repo|home_domain|rsver"
echo "$META" | grep -q "source_repo: github:$REPO" \
    || { echo "*** source_repo missing; stopping"; exit 1; }

echo
echo "== 2. attestation"
gh attestation verify $WASM --repo $REPO --signer-workflow $SIGNER \
    --source-ref $TAG_REF --source-digest $COMMIT >/dev/null \
    || { echo "*** attestation does not verify; stopping"; exit 1; }
echo "attested: $REPO @ $COMMIT ($TAG_REF), signed by $SIGNER"

echo
echo "== 3. fund multisig check"
curl -sf $HORIZON/accounts/$FUND | python3 -c '
import json, sys
d = json.load(sys.stdin)
t = d["thresholds"]
s = [(x["key"], x["weight"]) for x in d["signers"]]
for k, w in s: print("  signer", k, "weight", w)
print("  thresholds", t)
ok = (len(s) == 3 and all(w == 1 for _, w in s)
      and t["low_threshold"] == t["med_threshold"] == t["high_threshold"] == 2
      and not d["data"])
sys.exit(0 if ok else 1)
' || { echo "*** fund is not a clean 2-of-3; stopping"; exit 1; }

echo
echo "== 4. address"
ID=$(stellar contract id wasm --salt $SALT --source-account $SOURCE --network mainnet)
echo "controller address will be $ID"
[ "$ID" = "$EXPECTED" ] || { echo "*** expected $EXPECTED; stopping"; exit 1; }

echo
echo "admin $FUND (fund multisig), not upgradeable, admin can't be changed."
read -p "Upload and deploy? [y/N] " ok
[ "$ok" = y ] || { echo "stopped; nothing sent"; exit 0; }

echo "== 5. upload + deploy (sends)"
HASH=$(stellar contract upload --source-account $SOURCE --network mainnet --wasm $WASM | tail -1)
echo "wasm hash $HASH"
[ "$HASH" = "$WASM_SHA256" ] || { echo "*** uploaded hash differs; stopping"; exit 1; }
stellar contract deploy --source-account $SOURCE --network mainnet \
    --wasm-hash $HASH --salt $SALT -- --admin $FUND

echo "== 6. verify"
inv() { stellar contract invoke --source-account $SOURCE --network mainnet --send no --id $ID -- "$@" | tail -1; }
echo "admin:       $(inv admin)"
echo "permissions: $(inv permissions --pool $ID --user $FUND)   (expect 3)"
echo
echo "Next: ./deploy-pool-covered.sh"
