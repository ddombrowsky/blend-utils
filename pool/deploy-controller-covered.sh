#!/bin/bash
# Step 0b of cover-reserve.txt: deploy the Blent Covered Pool access
# controller (covered-controller/), admin = the fund multisig.
#
# Fixed salt, so the address is known in advance:
#   CA5QQDOQBJ6DVPPET7HTBXUJIWZ6NEXDBBNGNNLN4LOXCCCC6MHTIBY5
# deploy-pool-covered.sh binds this address immutably.
#
# Rebuilds the wasm, checks its hash and the fund's signers, asks, then
# uploads + deploys and reads the contract back.

set -e
cd "$(dirname "$0")"

SOURCE=xbull                     # pays fees only; has no power over the controller
FUND=GDA5JJFUAGFBNT4BMEGASY7EWBJFOWL2VBXMYY6QKCEOZMXHX6BBXYOB
SALT=ede0646e028510e11980d4c14c5f9a8bbbf174b71d42d86db9d9dd5a03ee4960
EXPECTED=CA5QQDOQBJ6DVPPET7HTBXUJIWZ6NEXDBBNGNNLN4LOXCCCC6MHTIBY5
WASM=covered-controller/target/optimized/covered_controller.wasm
WASM_SHA256=b76964d5dbc95a6e531dae122054a838b1bcd603a99313d7577094c581e11efc
HORIZON=https://horizon.stellar.org

echo "== 1. build"
# build from inside the crate so rustup uses its pinned 1.91.1 toolchain
# (the hash depends on the rustc version)
(cd covered-controller && stellar contract build --locked --out-dir target/optimized >/dev/null)
SHA=$(sha256sum $WASM | cut -d' ' -f1)
echo "wasm sha256 $SHA"
if [ "$SHA" != "$WASM_SHA256" ]; then
    echo "*** expected $WASM_SHA256 (source changed?); stopping"
    exit 1
fi

echo
echo "== 2. fund multisig check"
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
echo "== 3. address"
ID=$(stellar contract id wasm --salt $SALT --source-account $SOURCE --network mainnet)
echo "controller address will be $ID"
[ "$ID" = "$EXPECTED" ] || { echo "*** expected $EXPECTED; stopping"; exit 1; }

echo
echo "admin $FUND (fund multisig), not upgradeable, admin can't be changed."
read -p "Upload and deploy? [y/N] " ok
[ "$ok" = y ] || { echo "stopped; nothing sent"; exit 0; }

echo "== 4. upload + deploy (sends)"
HASH=$(stellar contract upload --source-account $SOURCE --network mainnet --wasm $WASM | tail -1)
echo "wasm hash $HASH"
stellar contract deploy --source-account $SOURCE --network mainnet \
    --wasm-hash $HASH --salt $SALT -- --admin $FUND

echo "== 5. verify"
inv() { stellar contract invoke --source-account $SOURCE --network mainnet --send no --id $ID -- "$@" | tail -1; }
echo "admin:       $(inv admin)"
echo "permissions: $(inv permissions --pool $ID --user $FUND)   (expect 3)"
echo
echo "Next: ./deploy-pool-covered.sh"
