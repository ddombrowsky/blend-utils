#!/usr/bin/env node
'use strict';

/**
 * BLND/USDC Arbitrage Bot — Comet AMM vs SDEX
 *
 * Two directions:
 *   A) Buy BLND on Comet (USDC→BLND), sell BLND on SDEX via pathPaymentStrictSend
 *   B) Buy BLND on SDEX via pathPaymentStrictSend (USDC→BLND), sell BLND on Comet
 *
 * Usage:
 *   export SECRET_KEY=$(stellar keys show <name>)
 *   node arb.js [--execute] [--usdc 10] [--min-profit 0.5] [--poll 5] [--max-fee 1]
 *
 * Flags:
 *   --execute           Submit real transactions (default: dry-run / simulate only)
 *   --usdc <n>          USDC trade size per arb cycle (default: 10)
 *   --min-profit <n>    Minimum gross profit % before executing arb (default: 0.5)
 *   --poll <n>          Seconds between polls (default: 5)
 *   --max-fee <n>       Max Soroban fee in XLM (default: 1)
 *   --rebalance <n>     Rebalance threshold in USD (default: 0.06)
 */

const Stellar = require('@stellar/stellar-sdk');
const {
  rpc: SorobanRpc, Horizon, Networks,
  TransactionBuilder, Contract, Account,
  Asset, Operation, Keypair,
  nativeToScVal, scValToNative,
} = Stellar;

// ── CLI args ─────────────────────────────────────────────────────────────────
const argv    = process.argv.slice(2);
const getArg  = (f, def) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : def; };
const hasFlag = (f) => argv.includes(f);

const EXECUTE             = hasFlag('--execute');
const USDC_TRADE          = parseFloat(getArg('--usdc', '10'));
const MIN_PROFIT_PCT      = parseFloat(getArg('--min-profit', '0.5'));
const POLL_MS             = parseInt(getArg('--poll', '5'), 10) * 1000;
const MAX_FEE_XLM         = parseFloat(getArg('--max-fee', '1'));
const MAX_FEE_STR         = Math.round(MAX_FEE_XLM * 1e7).toString();
const REBALANCE_THRESHOLD = parseFloat(getArg('--rebalance', '0.06')); // USD imbalance to trigger
const SLIPPAGE            = 0.005; // 0.5% slippage tolerance on each leg

// ── Addresses ─────────────────────────────────────────────────────────────────
const COMET_POOL  = 'CAS3FL6TLZKDGGSISDBWGGPXT3NRR4DYTZD7YOD3HMYO6LTJUVGRVEAM';
const BLND_TOKEN  = 'CD25MNVTZDL4Y3XBCPCJXGXATV5WUHHOWMYFF4YBEGU5FCPGMYTVG5JY';
const USDC_TOKEN  = 'CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75';
const BLND_ISSUER = 'GDJEHTBE6ZHUXSWFI642DCGLUOECLHPF3KSXHPXTSTJ7E3JF6MQ5EZYY';
const USDC_ISSUER = 'GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN';

const HORIZON_URL = 'https://horizon.stellar.org';
const RPC_URL     = 'https://soroban-rpc.creit.tech';

const blndAsset = new Asset('BLND', BLND_ISSUER);
const usdcAsset = new Asset('USDC', USDC_ISSUER);

// Very large max_price for Comet swaps (no effective upper bound on price)
// 10000 USDC per BLND — stored as plain number since it fits in MAX_SAFE_INTEGER
const MAX_PRICE_UNITS = 10000 * 1e7;

// ── Keypair ───────────────────────────────────────────────────────────────────
const SECRET_KEY = process.env.SECRET_KEY;
if (!SECRET_KEY) {
  console.error('ERROR: SECRET_KEY env var is not set.');
  console.error('  Run: export SECRET_KEY=$(stellar keys show <name>)');
  process.exit(1);
}
const keypair   = Keypair.fromSecret(SECRET_KEY);
const walletPub = keypair.publicKey();

// ── ScVal helpers ─────────────────────────────────────────────────────────────
const i128 = (n) => nativeToScVal(typeof n === 'bigint' ? n : BigInt(Math.round(n)), { type: 'i128' });
const addr  = (s) => nativeToScVal(s, { type: 'address' });

// ── P&L / activity tracker ────────────────────────────────────────────────────
const pnl = { trades: 0, grossProfit: 0, skipped: 0, rebalances: 0 };

// ── Utilities ─────────────────────────────────────────────────────────────────
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function log(msg) {
  process.stdout.write(`[${new Date().toISOString().slice(11, 19)}] ${msg}\n`);
}

function fmtUsdc(n) { return n == null ? 'N/A' : n.toFixed(6); }

// Parse path from Horizon strictSendPaths record into Asset array
function parsePath(record) {
  return (record.path || []).map((p) =>
    p.asset_type === 'native' ? Asset.native() : new Asset(p.asset_code, p.asset_issuer)
  );
}

// ── Soroban view calls ────────────────────────────────────────────────────────
async function cometSpotPrice(rpc, tokenIn, tokenOut) {
  // get_spot_price(token_in, token_out) → i128  (spot price * 1e7, token_in per token_out)
  // Works cleanly as a view call without needing real token balances.
  const op      = new Contract(COMET_POOL).call('get_spot_price', addr(tokenIn), addr(tokenOut));
  const account = new Account(walletPub, '0');
  const tx      = new TransactionBuilder(account, {
    fee: MAX_FEE_STR, networkPassphrase: Networks.PUBLIC,
  }).addOperation(op).setTimeout(60).build();
  const sim = await rpc.simulateTransaction(tx);
  if (SorobanRpc.Api.isSimulationError(sim)) throw new Error('get_spot_price: ' + sim.error);
  return Number(scValToNative(sim.result.retval)) / 1e7;
}

// ── Wallet balance helpers ────────────────────────────────────────────────────

// Query a Soroban token's balance for walletPub.
// USDC_TOKEN and BLND_TOKEN are Stellar Asset Contracts (SACs), so their
// balance() returns the same value as the classic Stellar asset balance.
async function tokenBalance(rpc, tokenContract) {
  const op      = new Contract(tokenContract).call('balance', addr(walletPub));
  const account = new Account(walletPub, '0');
  const tx      = new TransactionBuilder(account, {
    fee: '100', networkPassphrase: Networks.PUBLIC,
  }).addOperation(op).setTimeout(60).build();
  const sim = await rpc.simulateTransaction(tx);
  if (SorobanRpc.Api.isSimulationError(sim)) return 0; // account may not hold the token yet
  return Number(scValToNative(sim.result.retval)) / 1e7;
}

// Returns current wallet balances and the USD-value imbalance.
// diff > 0 means wallet is USDC-heavy; diff < 0 means BLND-heavy.
async function getWalletBalances(rpc, cometUsdcPerBlnd) {
  const [usdc, blnd] = await Promise.all([
    tokenBalance(rpc, USDC_TOKEN),
    tokenBalance(rpc, BLND_TOKEN),
  ]);
  const blndUsd = blnd * cometUsdcPerBlnd;
  const total   = usdc + blndUsd;
  const diff    = usdc - blndUsd;
  return { usdc, blnd, blndUsd, total, diff };
}

// ── Opportunity detection ─────────────────────────────────────────────────────
// Uses get_spot_price for the Comet side (price impact of our trade size vs the
// 836 K USDC pool is <0.01%) and strictSendPaths for real SDEX effective rates.
//
// cometUsdcPerBlnd is pre-fetched by poll() and shared with getWalletBalances()
// to avoid a redundant RPC round-trip.
async function checkOpportunity(rpc, horizon, cometUsdcPerBlnd) {
  const results = [];

  // Fetch the reverse Comet price and SDEX paths concurrently
  const blndEquiv = USDC_TRADE / cometUsdcPerBlnd; // ~BLND we'd get buying on Comet
  const [cometBlndPerUsdc, sellPath, buyPath] = await Promise.all([
    cometSpotPrice(rpc, BLND_TOKEN, USDC_TOKEN),
    horizon.strictSendPaths(blndAsset, blndEquiv.toFixed(7), [usdcAsset]).call(),
    horizon.strictSendPaths(usdcAsset, USDC_TRADE.toFixed(7), [blndAsset]).call(),
  ]);

  // ── Direction A: Comet USDC→BLND, then SDEX BLND→USDC ───────────────────
  if (sellPath.records.length > 0) {
    const sdexUsdcPerBlnd = parseFloat(sellPath.records[0].destination_amount) / blndEquiv;
    // Profit: sell BLND on SDEX at sdexUsdcPerBlnd, bought at cometUsdcPerBlnd
    const profit    = (sdexUsdcPerBlnd - cometUsdcPerBlnd) * blndEquiv;
    const profitPct = (sdexUsdcPerBlnd - cometUsdcPerBlnd) / cometUsdcPerBlnd * 100;
    const blndUnits = Math.round(blndEquiv * 1e7);
    results.push({
      dir: 'A',
      label: 'Comet(USDC→BLND) → SDEX(BLND→USDC)',
      usdcIn: USDC_TRADE,
      blndMid: blndEquiv,
      blndUnits,
      cometPrice: cometUsdcPerBlnd,
      sdexPrice: sdexUsdcPerBlnd,
      usdcOut: USDC_TRADE + profit,
      profit,
      profitPct,
      sdexRecord: sellPath.records[0],
      leg1: 'comet-buy',
    });
  }

  // ── Direction B: SDEX USDC→BLND, then Comet BLND→USDC ───────────────────
  // How much BLND does SDEX give for USDC_TRADE USDC?
  if (buyPath.records.length > 0) {
    const blndFromSdex    = parseFloat(buyPath.records[0].destination_amount);
    const sdexUsdcPerBlnd = USDC_TRADE / blndFromSdex;   // effective USDC paid per BLND
    // cometBlndPerUsdc = BLND cost per USDC on Comet → invert to get USDC per BLND
    const cometUsdcPerBlndSell = 1 / cometBlndPerUsdc;
    // Profit: sell BLND on Comet at cometUsdcPerBlndSell, bought at sdexUsdcPerBlnd
    const profit    = (cometUsdcPerBlndSell - sdexUsdcPerBlnd) * blndFromSdex;
    const profitPct = (cometUsdcPerBlndSell - sdexUsdcPerBlnd) / sdexUsdcPerBlnd * 100;
    const blndUnits = Math.round(blndFromSdex * 1e7);
    results.push({
      dir: 'B',
      label: 'SDEX(USDC→BLND) → Comet(BLND→USDC)',
      usdcIn: USDC_TRADE,
      blndMid: blndFromSdex,
      blndUnits,
      cometPrice: cometUsdcPerBlndSell,
      sdexPrice: sdexUsdcPerBlnd,
      usdcOut: USDC_TRADE + profit,
      profit,
      profitPct,
      sdexRecord: buyPath.records[0],
      leg1: 'sdex-buy',
    });
  }

  if (results.length === 0) return null;
  results.sort((a, b) => b.profitPct - a.profitPct);
  return results[0];
}

// ── Soroban execution ─────────────────────────────────────────────────────────
// Derives min_amount_out from the *actual* simulated output rather than a naive
// spot-price estimate. Comet's swap fee makes the spot estimate optimistic, which
// caused ERR_LIMIT_OUT (Error(Contract, #20)) when the shortfall exceeded our
// slippage tolerance. By sizing the floor off the real sim, slippage protection
// guards only the gap between simulation and on-chain execution — which is its job.
async function executeCometSwap(rpc, tokenIn, amtInUnits, tokenOut, slippage = SLIPPAGE) {
  // TransactionBuilder mutates the account's sequence on build(), so each tx needs
  // its own account object. Simulation ignores the sequence, so the discovery pass
  // uses a throwaway account; only the real (submitted) tx needs the live sequence.
  const buildTx = (account, minOutUnits) => {
    const op = new Contract(COMET_POOL).call(
      'swap_exact_amount_in',
      addr(tokenIn),
      i128(amtInUnits),
      addr(tokenOut),
      i128(minOutUnits),
      i128(MAX_PRICE_UNITS),
      addr(walletPub),
    );
    return new TransactionBuilder(account, {
      fee: MAX_FEE_STR,
      networkPassphrase: Networks.PUBLIC,
    }).addOperation(op).setTimeout(60).build();
  };

  // Pass 1 — discover the real output with a negligible floor (1 unit) so the
  // contract doesn't reject on ERR_LIMIT_OUT before we know the true amount.
  const discoverSim = await rpc.simulateTransaction(buildTx(new Account(walletPub, '0'), 1));
  if (SorobanRpc.Api.isSimulationError(discoverSim)) {
    throw new Error('Comet discover sim error: ' + discoverSim.error);
  }
  const expectedOut  = Number(scValToNative(discoverSim.result.retval)[0]); // units (×1e7)
  const minOutUnits  = Math.max(1, Math.floor(expectedOut * (1 - slippage)));
  log(`    Expected out ${(expectedOut / 1e7).toFixed(6)} — min ${(minOutUnits / 1e7).toFixed(6)} (${(slippage * 100).toFixed(2)}% slip)`);

  // Pass 2 — real tx with the live sequence and the slippage-protected minimum.
  // In @stellar/stellar-sdk the returned object has .accountId()/.sequenceNumber() methods.
  const accData = await rpc.getAccount(walletPub);
  const tx  = buildTx(accData, minOutUnits);
  const sim = await rpc.simulateTransaction(tx);
  if (SorobanRpc.Api.isSimulationError(sim)) {
    throw new Error('Comet exec sim error: ' + sim.error);
  }

  // Assemble (applies soroban auth + resource footprint from simulation)
  const assembled = SorobanRpc.assembleTransaction(tx, sim).build();
  assembled.sign(keypair);

  log(`    Submitting Soroban tx...`);
  const sendResp = await rpc.sendTransaction(assembled);

  if (sendResp.status === 'ERROR') {
    throw new Error('sendTransaction ERROR: ' + JSON.stringify(sendResp.errorResult));
  }

  // Poll for finality
  const hash = sendResp.hash;
  log(`    Soroban tx hash: ${hash} — polling...`);
  for (let i = 0; i < 40; i++) {
    await sleep(3000);
    const status = await rpc.getTransaction(hash);
    if (status.status === 'SUCCESS') {
      // Parse amount_out from result
      let amtOut = null;
      try {
        const native = scValToNative(status.returnValue);
        amtOut = Number(native[0]) / 1e7;
      } catch (_) {}
      log(`    Soroban SUCCESS — got ${amtOut != null ? amtOut.toFixed(6) : '?'} out`);
      return { hash, amtOut };
    }
    if (status.status === 'FAILED') {
      throw new Error(`Soroban tx FAILED: ${hash}`);
    }
  }
  throw new Error(`Soroban tx timed out: ${hash}`);
}

// ── SDEX path payment execution ───────────────────────────────────────────────
async function executeSdexPath(horizon, sendAsset, sendAmt, destAsset, destMin, sdexRecord) {
  const path    = parsePath(sdexRecord);
  const account = await horizon.loadAccount(walletPub);

  const op = Operation.pathPaymentStrictSend({
    sendAsset,
    sendAmount: sendAmt.toFixed(7),
    destination: walletPub,
    destAsset,
    destMin: destMin.toFixed(7),
    path,
  });

  const tx = new TransactionBuilder(account, {
    fee: '1000000',               // 0.1 XLM max for classic op
    networkPassphrase: Networks.PUBLIC,
  }).addOperation(op).setTimeout(60).build();

  tx.sign(keypair);

  log(`    Submitting SDEX path payment...`);
  const resp = await horizon.submitTransaction(tx);
  if (!resp.successful) {
    const codes = resp.extras?.result_codes;
    throw new Error(`SDEX tx failed: ${JSON.stringify(codes)}`);
  }
  log(`    SDEX SUCCESS — tx: ${resp.hash}`);
  return { hash: resp.hash };
}

// ── Execute arbitrage ─────────────────────────────────────────────────────────
async function executeArb(rpc, horizon, opp) {
  const usdcUnits   = Math.round(opp.usdcIn * 1e7);
  const blndUnits   = opp.blndUnits;
  const blndAmt     = opp.blndMid;

  // SDEX-leg minima (Comet legs derive their own floor inside executeCometSwap)
  const minUsdcBack = opp.usdcIn * (1 - SLIPPAGE); // at worst break-even minus slippage

  if (opp.dir === 'A') {
    // Leg 1: Comet USDC→BLND
    log(`  Leg 1 — Comet swap: ${opp.usdcIn} USDC → BLND`);
    const leg1 = await executeCometSwap(rpc, USDC_TOKEN, usdcUnits, BLND_TOKEN);
    const blndToSell = leg1.amtOut ?? blndAmt * (1 - SLIPPAGE);

    // Leg 2: SDEX BLND→USDC
    log(`  Leg 2 — SDEX path: ${blndToSell.toFixed(6)} BLND → USDC (min ${minUsdcBack.toFixed(4)})`);
    const leg2 = await executeSdexPath(horizon, blndAsset, blndToSell, usdcAsset, minUsdcBack, opp.sdexRecord);
    return { leg1, leg2 };

  } else {
    // Leg 1: SDEX USDC→BLND
    const minBlndFromSdex = blndAmt * (1 - SLIPPAGE);
    log(`  Leg 1 — SDEX path: ${opp.usdcIn} USDC → BLND (min ${minBlndFromSdex.toFixed(4)})`);
    const leg1 = await executeSdexPath(horizon, usdcAsset, opp.usdcIn, blndAsset, minBlndFromSdex, opp.sdexRecord);

    // Leg 2: Comet BLND→USDC
    log(`  Leg 2 — Comet swap: ${blndAmt.toFixed(6)} BLND → USDC`);
    const leg2 = await executeCometSwap(rpc, BLND_TOKEN, blndUnits, USDC_TOKEN);
    return { leg1, leg2 };
  }
}

// ── Main poll loop ────────────────────────────────────────────────────────────
let iteration = 0;

async function poll(rpc, horizon) {
  iteration++;
  const ts = new Date().toISOString().replace('T', ' ').slice(0, 19);
  log(`Poll #${iteration} — ${ts} | ${EXECUTE ? 'LIVE' : 'DRY-RUN'}`);

  // ── Fetch Comet spot price first — shared by arb check AND balance valuation ──
  let cometUsdcPerBlnd;
  try {
    cometUsdcPerBlnd = await cometSpotPrice(rpc, USDC_TOKEN, BLND_TOKEN);
  } catch (e) {
    log(`  Price fetch failed: ${e.message}`);
    return;
  }

  // ── Run balance query and arb opportunity check concurrently ──────────────
  const [balRes, oppRes] = await Promise.allSettled([
    getWalletBalances(rpc, cometUsdcPerBlnd),
    checkOpportunity(rpc, horizon, cometUsdcPerBlnd),
  ]);

  const bal = balRes.status === 'fulfilled' ? balRes.value : null;
  const opp = oppRes.status === 'fulfilled' ? oppRes.value : null;
  if (balRes.status === 'rejected') log(`  Balance query error: ${balRes.reason?.message}`);
  if (oppRes.status === 'rejected') log(`  Opp check error:    ${oppRes.reason?.message}`);

  // ── 1. Display wallet balances ────────────────────────────────────────────
  if (bal) {
    const absDiff = Math.abs(bal.diff);
    const heavy   = absDiff <= REBALANCE_THRESHOLD
      ? 'balanced ✓'
      : bal.diff > 0 ? `USDC heavy  Δ$${absDiff.toFixed(4)}` : `BLND heavy  Δ$${absDiff.toFixed(4)}`;
    log(`  Wallet: ${bal.usdc.toFixed(4)} USDC | ${bal.blnd.toFixed(4)} BLND (~$${bal.blndUsd.toFixed(4)}) | total $${bal.total.toFixed(4)} | ${heavy}`);
  }

  // ── 2. Arbitrage check ────────────────────────────────────────────────────
  if (opp) {
    const sign = opp.profitPct >= 0 ? '+' : '';
    log(`  Arb  [${opp.dir}] ${opp.label}`);
    log(`    Comet ${opp.cometPrice.toFixed(6)} USDC/BLND | SDEX ${opp.sdexPrice.toFixed(6)} | spread ${sign}${opp.profitPct.toFixed(3)}%`);
    log(`    ${opp.usdcIn.toFixed(4)} USDC → ${opp.blndMid.toFixed(4)} BLND → ${fmtUsdc(opp.usdcOut)} USDC  (${sign}${opp.profit.toFixed(6)} USDC)`);

    if (opp.profitPct >= MIN_PROFIT_PCT) {
      log(`  *** ARB SIGNAL: ${opp.profitPct.toFixed(3)}% >= ${MIN_PROFIT_PCT}% ***`);
      if (EXECUTE) {
        try {
          await executeArb(rpc, horizon, opp);
          pnl.trades++;
          pnl.grossProfit += opp.profit;
          log(`  Arb done — session gross P&L: +${pnl.grossProfit.toFixed(6)} USDC over ${pnl.trades} trade(s)`);
        } catch (e) {
          log(`  Arb execution error: ${e.message}`);
        }
      } else {
        log('  [DRY-RUN] Would execute arb. Pass --execute to trade.');
      }
    } else {
      pnl.skipped++;
      log(`  Arb below threshold (${MIN_PROFIT_PCT}%) — skipping.`);
    }
  } else {
    log('  Arb: no opportunity this cycle.');
  }

  // ── 3. Balance rebalancing ────────────────────────────────────────────────
  if (!bal) return;

  const absDiff = Math.abs(bal.diff);
  if (absDiff <= REBALANCE_THRESHOLD) return; // within tolerance

  // Amount to swap to reach 50/50: half the imbalance (in USD)
  const rebalUsd = absDiff / 2;

  if (bal.diff > 0) {
    // USDC heavy → buy BLND with rebalUsd USDC on Comet
    const blndExpected = rebalUsd / cometUsdcPerBlnd;
    const usdcUnits    = Math.round(rebalUsd * 1e7);
    log(`  Rebalance: USDC heavy by $${absDiff.toFixed(4)} — buying ~${blndExpected.toFixed(4)} BLND with ${rebalUsd.toFixed(4)} USDC on Comet`);
    if (EXECUTE) {
      try {
        await executeCometSwap(rpc, USDC_TOKEN, usdcUnits, BLND_TOKEN);
        pnl.rebalances++;
        log(`  Rebalance done (${pnl.rebalances} total).`);
      } catch (e) {
        log(`  Rebalance error: ${e.message}`);
      }
    } else {
      log(`  [DRY-RUN] Would swap ${rebalUsd.toFixed(4)} USDC → ~${blndExpected.toFixed(4)} BLND`);
    }
  } else {
    // BLND heavy → sell rebalUsd-worth of BLND for USDC on Comet
    const blndToSell = rebalUsd / cometUsdcPerBlnd;
    const blndUnits  = Math.round(blndToSell * 1e7);
    log(`  Rebalance: BLND heavy by $${absDiff.toFixed(4)} — selling ${blndToSell.toFixed(4)} BLND for ~${rebalUsd.toFixed(4)} USDC on Comet`);
    if (EXECUTE) {
      try {
        await executeCometSwap(rpc, BLND_TOKEN, blndUnits, USDC_TOKEN);
        pnl.rebalances++;
        log(`  Rebalance done (${pnl.rebalances} total).`);
      } catch (e) {
        log(`  Rebalance error: ${e.message}`);
      }
    } else {
      log(`  [DRY-RUN] Would swap ${blndToSell.toFixed(4)} BLND → ~$${rebalUsd.toFixed(4)} USDC`);
    }
  }
}

async function main() {
  const rpc     = new SorobanRpc.Server(RPC_URL);
  const horizon = new Horizon.Server(HORIZON_URL);

  console.log('');
  console.log('BLND/USDC Arbitrage + Rebalance Bot');
  console.log(`  Wallet         : ${walletPub}`);
  console.log(`  Arb trade size : ${USDC_TRADE} USDC`);
  console.log(`  Arb threshold  : ${MIN_PROFIT_PCT}% gross profit`);
  console.log(`  Rebal threshold: $${REBALANCE_THRESHOLD.toFixed(2)} USD imbalance`);
  console.log(`  Slippage floor : ${(SLIPPAGE * 100).toFixed(1)}% per leg`);
  console.log(`  Poll           : ${POLL_MS / 1000}s`);
  console.log(`  Mode           : ${EXECUTE ? '*** LIVE EXECUTION ***' : 'DRY-RUN (pass --execute to trade)'}`);
  console.log('');

  process.on('SIGINT', () => {
    console.log('\n');
    console.log('── Session summary ──────────────────────────────');
    console.log(`  Arb trades      : ${pnl.trades}`);
    console.log(`  Gross arb P&L   : +${pnl.grossProfit.toFixed(6)} USDC`);
    console.log(`  Arb skipped     : ${pnl.skipped}`);
    console.log(`  Rebalances done : ${pnl.rebalances}`);
    console.log('─────────────────────────────────────────────────');
    process.exit(0);
  });

  while (true) {
    try {
      await poll(rpc, horizon);
    } catch (e) {
      log(`Poll error: ${e.message}`);
    }
    await sleep(POLL_MS);
  }
}

main();
