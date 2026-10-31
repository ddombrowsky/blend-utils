#!/bin/sh

# https://github.com/BLNT-Protocol/blnt-contracts-v3/blob/main/pool/src/errors.rs
# error 1200 = bad request (wrong user / percent != 100)
# error 1212 = auction in progress (the last interest auction isn't filled yet)
# error 1227 = invalid interest auction (v3 lots have max of 4 assets)
# error 1228 = no interest auction capacity (not enough interest accrued yet)

LOG=auction.log

# BLNT v3 fixed
echo BLNT v3 fixed
stellar contract invoke \
    --id CACSQWCMKG45TUHCQ3LXHOB7YEEJH4W376ZHQPXH2IZ3TE4NJHFZMCY7 \
    --source-account xbull \
    --network mainnet --fee 10000000 -- \
    new_auction \
      --percent 100 \
      --lot '["CAS3J7GYLGXMF6TDJBBYYSE3HQ6BBSMLNUQ34T6TZMYMW2EVH34XOWMA","CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75","CDTKPWPLOURQA2SGTKTUQOWRCBZEORB4BWBOMJ3D3ZTQQSGE5F6JBQLV"]' \
      --user 'CAHCUKBPTW5DR5RNXOHCTJD5U76A6EEZXYZAQFRQEEQRXQ3CRUZ6Z3MO' \
      --auction_type 2 \
      --bid '[]' > \
    $LOG 2>&1
    grep Error $LOG || exit
grep -q 'Error(Contract, #1228)' $LOG || exit

# Not enough interest: show what each backstop tier has accrued, computed the
# way tier_interest.rs does it.  Credit not yet checkpointed into the stored
# per-tier state (all of it, until an auction is actually created) is split
# by tier value * take_rate_weight; each tier needs $20 across the lot.
python3 - <<'EOF'
import json, subprocess

POOL = "CACSQWCMKG45TUHCQ3LXHOB7YEEJH4W376ZHQPXH2IZ3TE4NJHFZMCY7"
BACKSTOP = "CAHCUKBPTW5DR5RNXOHCTJD5U76A6EEZXYZAQFRQEEQRXQ3CRUZ6Z3MO"
LOT = {
    "CAS3J7GYLGXMF6TDJBBYYSE3HQ6BBSMLNUQ34T6TZMYMW2EVH34XOWMA": "XLM",
    "CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75": "USDC",
    "CDTKPWPLOURQA2SGTKTUQOWRCBZEORB4BWBOMJ3D3ZTQQSGE5F6JBQLV": "EURC",
}
TIER_FIELDS = ["first_loss", "second_loss", "third_loss"]
MIN_LOT_USD = 20

def stellar(*args, input=None):
    return subprocess.run(["stellar", *args], input=input, capture_output=True,
                          text=True, check=True).stdout.strip()

def invoke(contract, *args):
    return json.loads(stellar("contract", "invoke", "--id", contract,
                              "--source-account", "xbull", "--network",
                              "mainnet", "--send", "no", "--", *args))

def stored_state(asset):
    # InterestDataKey::Reserve(asset); missing until an auction is created
    state = dict.fromkeys(["carry"] + TIER_FIELDS, 0)
    key = stellar("xdr", "encode", "--type", "ScVal", input=json.dumps(
        {"vec": [{"symbol": "Reserve"}, {"address": asset}]}))
    try:
        entry = stellar("contract", "read", "--id", POOL, "--network",
                        "mainnet", "--durability", "persistent",
                        "--key-xdr", key, "--output", "xdr")
    except subprocess.CalledProcessError:
        return state
    val = stellar("xdr", "decode", "--type", "ScVal", "--output", "json",
                  input=entry.split(",")[1])
    for field in json.loads(val)["map"]:
        state[field["key"]["symbol"]] = int(field["val"]["i128"])
    return state

oracle = invoke(POOL, "get_config")["oracle"]
oracle_scalar = 10 ** invoke(oracle, "decimals")
tiers = invoke(BACKSTOP, "pool_data", "--pool", POOL)["tiers"]
weights = [int(t["value"]) * t["take_rate_weight"] for t in tiers]
total_weight = sum(weights)

tier_usd = [0.0] * len(tiers)
rows = [[] for _ in tiers]
for asset, name in LOT.items():
    reserve = invoke(POOL, "get_reserve", "--asset", asset)
    scalar = int(reserve["scalar"])
    price = int(invoke(oracle, "lastprice", "--asset",
                       json.dumps({"Stellar": asset}))["price"]) / oracle_scalar
    state = stored_state(asset)
    new_credit = int(reserve["data"]["backstop_credit"]) - sum(
        state[f] for f in TIER_FIELDS)
    for i, field in enumerate(TIER_FIELDS[:len(tiers)]):
        amount = state[field]
        if total_weight and int(tiers[i]["value"]) > 0:
            amount += new_credit * weights[i] // total_weight
        tokens = amount / scalar
        tier_usd[i] += tokens * price
        rows[i].append(f"    {name:5} {tokens:12.7f}  (${tokens * price:.2f})")

print("Not enough interest for an auction. Accrued backstop credit per tier:")
for i, t in enumerate(tiers):
    share = 100 * weights[i] / total_weight if total_weight else 0
    print(f"  {t['asset']} ({share:.1f}%): ${tier_usd[i]:.2f} of ${MIN_LOT_USD}")
    print("\n".join(rows[i]))
EOF
