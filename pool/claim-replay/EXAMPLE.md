# Reproduce a YieldBlent claim after the Comet market changes

A claim that would receive **0.0506828 LP** receives **0.0501810 LP** after a
trade changes the BLNT:XLM Comet pool. The previous minimum rejects the claim
without consuming the reward. A retry with a recalculated minimum succeeds.

## Results

Saved mainnet ledger: **65,556,895**, **2026-11-19 06:41:58 UTC**. The existing
YieldBlent FirstLoss position has **0.5834575 BLNT** of claimable rewards in both
reference branches. All amounts below use seven decimals.

| Operation | Minimum LP | Actual LP | Result |
| --- | ---: | ---: | --- |
| Baseline measurement | 0 | 0.0506828 | Output before the market move |
| Post-trade measurement | 0 | 0.0501810 | Same reward amount, different output |
| Claim with the previous 0.5% tolerance | 0.0504293 | N/A | Comet error 20; no ledger changes |
| Retry with a new 0.5% tolerance | 0.0499300 | 0.0501810 | LP and owner/tier shares credited |
| Another claim at the same ledger time | 0.0499300 | 0 | The reward was consumed once |

The trade sells **53,104.8953513 BLNT**, one percent of the captured BLNT reserve,
for **2,234.5125525 XLM**. The trade remains applied after the rejected claim. The
retry credits **0.0501810 shares** to the same owner and tier; the other tier's user
balance is unchanged. Accepting the lower minimum does not restore the original
economic value.

See the [market-move assertions](tests/claim.rs#L331),
[Comet failure and rollback assertions](tests/claim.rs#L357), and
[retry and single-consumption assertions](tests/claim.rs#L407).

The test prints these raw amounts:

```text
reward=5834575 baseline_lp=506828 old_min=504293 changed_lp=501810
new_min=499300 retry_lp=501810 added_shares=501810
reserve_blnt=53104895351392 sold_blnt=531048953513 received_xlm=22345125525
rejection=Contract(20); unchanged_ledger=true; upstream_reads=0
```

## What the test covers

BLNT already has detailed minimum-output rollback tests with real Comet WASM
and synthetic state. This example exercises deployed bindings, actual reserves
and an existing accrued position, then introduces a real local Comet swap. It
provides a repeatable case for the isolated-WASM reproduction step in BLNT's
[immutable response plan](https://github.com/BLNT-Protocol/blnt-contracts-v3/blob/771059f6dd232fd35ea29b7b2a987f0e13bb2372/docs/IMMUTABLE_SECURITY_RESPONSE.md#L38-L48).
The reproduced refusal is expected behavior.

- Both branches start with identical state digests and keep ledger time fixed.
  The reward amount is measured in successful disposable reference branches.
- The failure's diagnostic event comes from the captured Comet contract. Its
  receipt has equal before/after ledger digests and an empty state diff, before
  the parent fork discards the failed operation.
- Retry assertions cover exact BLNT debit, Comet reserve increase, LP custody,
  share conversion, the same owner/tier, and a zero subsequent claim.
- The saved fixture contains 27 present and nine confirmed absent entries.
  Uncaptured dependencies fail closed; there is no network fallback during replay.

Owner authorization is mocked locally. A separate synthetic contract address
is funded through a local SAC `mint` with mocked token-admin authorization. Its
starting BLNT/XLM balances are checked as zero. Both branches receive identical
funding, without rewriting protocol accounting, reward accrual or Comet reserves.
Zero minima are only used for reference measurements; the rejected claim and
accepted retry use finite calculated minima.

This test loads no signing keys and sends no network transactions. It checks
contract execution and accounting, not signature validity, transaction admission,
network resource limits or fees. It does not invoke the lending pool's borrow or
liquidation entry points.

## Run the saved case

From `pool/claim-replay`, with Rust **1.95.0** installed:

```sh
cargo +1.95.0 fetch --locked
cargo +1.95.0 test --locked --offline -- --nocapture
```

The first command downloads dependencies, including **Kanatoko 29.1.2 from
crates.io**. The default test loads the saved fixture; the RPC capture test is
ignored. This package has its own lockfile and workspace, separate from the
covered controller and BLNT's production build.

Author validation also ran the test binary with all networking denied by the
operating system and separately confirmed that sockets were blocked. Formatting
and Clippy with warnings denied passed. These are author-run checks.

## Capture another current state

The opt-in test only reads public RPC. Supply a new output path; an existing file
is not overwritten. It runs the complete scenario against the new capture too.

```sh
BLNT_NEW_CAPTURE=/tmp/blnt-claim-new.json \
  cargo +1.95.0 test --locked --offline \
  capture_current_claim_and_market_dependencies -- --ignored --nocapture
```

The same recipe passed at ledger **65,556,945** without changing the source or
manually preparing state. Rewards had increased to **0.5836374 BLNT**; baseline
output was **0.0506985 LP** and post-trade/retry output was **0.0501965 LP**.

A new capture fails if rewards are no longer claimable, the market move no longer
crosses the specified tolerance, deployed code hashes change, or the network
protocol differs from the supported host. It does not silently adjust accounting
or skip those conditions.

## Provenance

Network and execution protocol: **29**. Saved ledger hash:
`7051b62652cc0e33fdc3ddf60f36dc599749df761800883ad820a17ca0710db4`.
Source RPC: `https://mainnet.sorobanrpc.com`.

The [test validates contract instance hashes and captured WASM bytes](tests/claim.rs#L244)
against the [BLNT core registry](https://github.com/BLNT-Protocol/blnt-contracts-v3/blob/771059f6dd232fd35ea29b7b2a987f0e13bb2372/deployments/mainnet-v3-core.json)
and [Comet registry](https://github.com/BLNT-Protocol/blnt-contracts-v3/blob/771059f6dd232fd35ea29b7b2a987f0e13bb2372/deployments/mainnet-v3-comet.json).
The YieldBlent position belongs to the public operator recorded in
[`pool/yieldblent.txt`](../yieldblent.txt); no owner key is needed for local replay.

| Artifact | SHA-256 |
| --- | --- |
| BLNT backstop | `0469cfb445bedd87478274f265c8776b32cde1e8840fca4684ffa1dc4d5a750f` |
| BLNT emitter | `4fa7d99dee6fe99cad5d07a46ee39e437dc287e53e3ab1f3ccc0aacf7e6cd6c5` |
| Comet V1.1, both canonical pools | `d735c3395f59510172cf5cf838823a1389b97cfec6bf24e580e9bd77d2b3e687` |

The captured WASMs retain their AGPL-3.0 licensing; see [LICENSE](LICENSE).
Corresponding source:
[BLNT `5d055ca89afc9ed443d36b7ad34e3de59b487764`](https://github.com/BLNT-Protocol/blnt-contracts-v3/tree/5d055ca89afc9ed443d36b7ad34e3de59b487764)
and [Comet `b3a2d827ed6c158341f8e67ea91eb3b0395d3871`](https://github.com/CometDEX/comet-contracts-v1/tree/b3a2d827ed6c158341f8e67ea91eb3b0395d3871).
