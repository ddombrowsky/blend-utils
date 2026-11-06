#!/usr/bin/env python3
"""Create a BLNT v3 interest auction for one pool.

    interest-v3.py [--dry-run] <name> <pool>

Reads every reserve's accrued backstop credit, split per backstop tier the way
tier_interest.rs does it, picks the (up to) 4 reserves with the most credit in
USD as the lot, and calls new_auction.  --dry-run simulates new_auction
instead of sending it.

https://github.com/BLNT-Protocol/blnt-contracts-v3/blob/main/pool/src/errors.rs
error 1200 = bad request (wrong user / percent != 100)
error 1212 = auction in progress (the last interest auction isn't filled yet)
error 1227 = invalid interest auction (v3 lots have max of 4 assets)
error 1228 = no interest auction capacity (not enough interest accrued yet)
"""
import json, re, subprocess, sys

BACKSTOP = "CAHCUKBPTW5DR5RNXOHCTJD5U76A6EEZXYZAQFRQEEQRXQ3CRUZ6Z3MO"
TIER_FIELDS = ["first_loss", "second_loss", "third_loss"]
MAX_LOT = 4
MIN_LOT_USD = 20
ERRORS = {
    1200: "bad request (wrong user / percent != 100)",
    1212: "auction in progress (last interest auction not filled yet)",
    1227: "invalid interest auction",
    1228: "not enough interest accrued yet",
}


def stellar(*args, input=None):
    return subprocess.run(["stellar", *args], input=input, capture_output=True,
                          text=True, check=True).stdout.strip()


def invoke(contract, *args):
    return json.loads(stellar("contract", "invoke", "--id", contract,
                              "--source-account", "xbull", "--network",
                              "mainnet", "--send", "no", "--", *args))


def stored_state(pool, asset):
    # InterestDataKey::Reserve(asset); missing until an auction is created
    state = dict.fromkeys(["carry"] + TIER_FIELDS, 0)
    key = stellar("xdr", "encode", "--type", "ScVal", input=json.dumps(
        {"vec": [{"symbol": "Reserve"}, {"address": asset}]}))
    try:
        entry = stellar("contract", "read", "--id", pool, "--network",
                        "mainnet", "--durability", "persistent",
                        "--key-xdr", key, "--output", "xdr")
    except subprocess.CalledProcessError:
        return state
    val = stellar("xdr", "decode", "--type", "ScVal", "--output", "json",
                  input=entry.split(",")[1])
    for field in json.loads(val)["map"]:
        state[field["key"]["symbol"]] = int(field["val"]["i128"])
    return state


def symbol(asset):
    try:
        sym = invoke(asset, "symbol")
        return "XLM" if sym == "native" else sym
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return asset[:6]


def tier_credit(pool):
    """Returns (tiers, weights, assets); assets is a list of
    (address, symbol, [usd per tier], [tokens per tier])."""
    oracle = invoke(pool, "get_config")["oracle"]
    oracle_scalar = 10 ** invoke(oracle, "decimals")
    tiers = invoke(BACKSTOP, "pool_data", "--pool", pool)["tiers"]
    weights = [int(t["value"]) * t["take_rate_weight"] for t in tiers]
    total_weight = sum(weights)

    assets = []
    for asset in invoke(pool, "get_reserve_list"):
        reserve = invoke(pool, "get_reserve", "--asset", asset)
        scalar = int(reserve["scalar"])
        price = int(invoke(oracle, "lastprice", "--asset", json.dumps(
            {"Stellar": asset}))["price"]) / oracle_scalar
        # Credit not yet checkpointed into the stored per-tier state (all of
        # it, until an auction is actually created) is split by tier value *
        # take_rate_weight.
        state = stored_state(pool, asset)
        new_credit = int(reserve["data"]["backstop_credit"]) - sum(
            state[f] for f in TIER_FIELDS)
        tokens, usd = [], []
        for i, field in enumerate(TIER_FIELDS[:len(tiers)]):
            amount = state[field]
            if total_weight and int(tiers[i]["value"]) > 0:
                amount += new_credit * weights[i] // total_weight
            tokens.append(amount / scalar)
            usd.append(amount / scalar * price)
        assets.append((asset, symbol(asset), usd, tokens))
    return tiers, weights, assets


def report(tiers, weights, assets, lot):
    total_weight = sum(weights)
    in_lot = [a for a in assets if a[0] in lot]
    print("Accrued backstop credit per tier (lot assets marked *):")
    for i, t in enumerate(tiers):
        share = 100 * weights[i] / total_weight if total_weight else 0
        lot_usd = sum(a[2][i] for a in in_lot)
        print(f"  {t['asset']} ({share:.1f}%): lot ${lot_usd:.2f}"
              f" of ${MIN_LOT_USD}")
        for addr, name, usd, tokens in assets:
            if tokens[i]:
                mark = "*" if addr in lot else " "
                print(f"   {mark}{name:8} {tokens[i]:14.7f}  (${usd[i]:.2f})")


def new_auction(pool, lot, dry_run):
    cmd = ["stellar", "contract", "invoke", "--id", pool,
           "--source-account", "xbull", "--network", "mainnet",
           "--fee", "10000000"]
    if dry_run:
        cmd += ["--send", "no"]
    cmd += ["--", "new_auction", "--percent", "100", "--lot", json.dumps(lot),
            "--user", BACKSTOP, "--auction_type", "2", "--bid", "[]"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    out = r.stdout + r.stderr
    m = re.search(r"Error\(Contract, #(\d+)\)", out)
    return r.returncode == 0, int(m.group(1)) if m else None, out


def main():
    args = sys.argv[1:]
    dry_run = "--dry-run" in args
    args = [a for a in args if a != "--dry-run"]
    if len(args) != 2:
        sys.exit(__doc__)
    name, pool = args

    print(f"== {name} {pool}")
    tiers, weights, assets = tier_credit(pool)
    ranked = sorted((a for a in assets if sum(a[2]) > 0),
                    key=lambda a: sum(a[2]), reverse=True)
    lot = [a[0] for a in ranked[:MAX_LOT]]
    if not lot:
        print("No accrued backstop credit.")
        return
    print("lot:", " ".join(a[1] for a in ranked[:MAX_LOT]))

    ok, code, out = new_auction(pool, lot, dry_run)
    if ok:
        print(("Simulated OK (dry run)" if dry_run else "Auction created") +
              ":\n" + out.strip())
        return
    if code:
        print(f"Error #{code}: {ERRORS.get(code, 'unknown')}")
    else:
        print(out.strip())
    if code in (1227, 1228):
        report(tiers, weights, assets, lot)


if __name__ == "__main__":
    main()
