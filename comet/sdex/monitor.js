#!/usr/bin/env node
'use strict';

/**
 * BLND/USDC oscillation monitor
 * Polls Comet AMM LP price and Stellar SDEX rates, shows spread / arb signal.
 *
 * Usage:  node monitor.js [poll_seconds]   (default: 5)
 */

const Stellar = require('@stellar/stellar-sdk');
const {
  Horizon, rpc: SorobanRpc, Networks,
  TransactionBuilder, Contract, Account,
  Asset, nativeToScVal, scValToNative,
} = Stellar;

// ── Contract / asset addresses ──────────────────────────────────────────────
const COMET_POOL  = 'CAS3FL6TLZKDGGSISDBWGGPXT3NRR4DYTZD7YOD3HMYO6LTJUVGRVEAM';
const BLND_TOKEN  = 'CD25MNVTZDL4Y3XBCPCJXGXATV5WUHHOWMYFF4YBEGU5FCPGMYTVG5JY';
const USDC_TOKEN  = 'CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75';
const BLND_ISSUER = 'GDJEHTBE6ZHUXSWFI642DCGLUOECLHPF3KSXHPXTSTJ7E3JF6MQ5EZYY';
const USDC_ISSUER = 'GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN';

// ── RPC / Horizon ────────────────────────────────────────────────────────────
const HORIZON_URL = 'https://horizon.stellar.org';
const RPC_URL     = 'https://soroban-rpc.creit.tech';

const POLL_MS     = parseInt(process.argv[2] || '5', 10) * 1000;

// Source account for read-only simulations (no signing — public key only needed)
const SIM_SOURCE  = 'GBTFQJ6VARJYI2C6JLPUXQ4CAKRNJF3KEYXXJ5T74DV47RSSNIJCH5VM'; // claudio

const blndAsset = new Asset('BLND', BLND_ISSUER);
const usdcAsset = new Asset('USDC', USDC_ISSUER);

// ── Soroban simulation helper ────────────────────────────────────────────────
async function simCall(rpc, contractId, method, ...args) {
  const op      = new Contract(contractId).call(method, ...args);
  const account = new Account(SIM_SOURCE, '0');
  const tx      = new TransactionBuilder(account, {
    fee: '100',
    networkPassphrase: Networks.PUBLIC,
  }).addOperation(op).setTimeout(30).build();

  const sim = await rpc.simulateTransaction(tx);
  if (SorobanRpc.Api.isSimulationError(sim)) {
    throw new Error(sim.error);
  }
  return sim.result?.retval;
}

function addrVal(contractId) {
  return nativeToScVal(contractId, { type: 'address' });
}

// ── Comet price sources ──────────────────────────────────────────────────────

// 1. get_spot_price(token_in, token_out) → i128 (scaled ×1e7)
//    Returns USDC per BLND (price of 1 BLND in USDC)
async function getCometSpotPrice(rpc) {
  const raw = await simCall(
    rpc, COMET_POOL, 'get_spot_price',
    addrVal(USDC_TOKEN), addrVal(BLND_TOKEN),
  );
  return Number(scValToNative(raw)) / 1e7; // USDC / BLND
}

// 2. get_spot_price_sans_fee — same but without swap fee
async function getCometSpotPriceSansFee(rpc) {
  const raw = await simCall(
    rpc, COMET_POOL, 'get_spot_price_sans_fee',
    addrVal(USDC_TOKEN), addrVal(BLND_TOKEN),
  );
  return Number(scValToNative(raw)) / 1e7;
}

// 3. Pool reserves via get_balance(token) → i128 (×1e7)
//    Mid price = USDC_balance / BLND_balance
async function getCometBalances(rpc) {
  const [blndRaw, usdcRaw] = await Promise.all([
    simCall(rpc, COMET_POOL, 'get_balance', addrVal(BLND_TOKEN)),
    simCall(rpc, COMET_POOL, 'get_balance', addrVal(USDC_TOKEN)),
  ]);
  const blnd = Number(scValToNative(blndRaw)) / 1e7;
  const usdc = Number(scValToNative(usdcRaw)) / 1e7;
  return { blnd, usdc, usdcPerBlnd: usdc / blnd };
}

async function getCometData(rpc) {
  const result = {};

  // Try get_spot_price first (includes swap fee, mirrors actual swap cost)
  try {
    result.spotPrice = await getCometSpotPrice(rpc);
  } catch (e) {
    result.spotPriceErr = e.message.slice(0, 80);
  }

  // Try get_spot_price_sans_fee (raw mid price)
  try {
    result.spotPriceSansFee = await getCometSpotPriceSansFee(rpc);
  } catch (e) {
    result.spotPriceSansFeeErr = e.message.slice(0, 80);
  }

  // Pool reserve balances (independent cross-check)
  try {
    result.balances = await getCometBalances(rpc);
  } catch (e) {
    result.balancesErr = e.message.slice(0, 80);
  }

  return result;
}

// ── SDEX data ────────────────────────────────────────────────────────────────
async function getSdexData(horizon) {
  // Orderbook: selling BLND, buying USDC
  const bookReq = horizon.orderbook(blndAsset, usdcAsset).call();

  // Path payments: effective rates for reference amounts
  const sell100Req = horizon.strictSendPaths(blndAsset, '100', [usdcAsset]).call();
  const buy5Req    = horizon.strictSendPaths(usdcAsset, '5',   [blndAsset]).call();

  const [book, sell100, buy5] = await Promise.all([bookReq, sell100Req, buy5Req]);

  const bestBid = book.bids.length > 0 ? parseFloat(book.bids[0].price) : null;
  const bestAsk = book.asks.length > 0 ? parseFloat(book.asks[0].price) : null;
  const spread  = (bestBid && bestAsk) ? (bestAsk - bestBid) / bestAsk * 100 : null;

  // Effective rate selling 100 BLND via path → USDC/BLND
  let pathSell = null;
  if (sell100.records.length > 0) {
    pathSell = parseFloat(sell100.records[0].destination_amount) / 100;
  }

  // Effective rate buying BLND with 5 USDC via path → BLND/USDC
  let pathBuy = null;
  if (buy5.records.length > 0) {
    pathBuy = parseFloat(buy5.records[0].destination_amount) / 5;
  }

  return { bestBid, bestAsk, spread, pathSell, pathBuy };
}

// ── Formatting helpers ───────────────────────────────────────────────────────
function f(n, d = 6) {
  return n == null ? 'N/A     ' : n.toFixed(d);
}

// Fixed-width row: "║  label: value  trailing ║"
// W=62 is the inner width between the box walls.
function row(label, value, trailing = '') {
  const inner = `    ${label}: ${value}  ${trailing}`;
  return `║${inner.padEnd(62)}║`;
}

function pctDiff(a, b) {
  if (a == null || b == null) return 'N/A';
  const p = (a - b) / b * 100;
  return (p >= 0 ? '+' : '') + p.toFixed(3) + '%';
}

// Price history for oscillation tracking (last N samples)
const HISTORY_LEN = 30;
const history = { comet: [], sdexBid: [], sdexAsk: [] };

function pushHistory(comet, bid, ask) {
  if (comet != null) { history.comet.push(comet); if (history.comet.length > HISTORY_LEN) history.comet.shift(); }
  if (bid   != null) { history.sdexBid.push(bid);  if (history.sdexBid.length > HISTORY_LEN) history.sdexBid.shift(); }
  if (ask   != null) { history.sdexAsk.push(ask);  if (history.sdexAsk.length > HISTORY_LEN) history.sdexAsk.shift(); }
}

function stats(arr) {
  if (arr.length < 2) return null;
  const min = Math.min(...arr), max = Math.max(...arr);
  const mean = arr.reduce((a, b) => a + b, 0) / arr.length;
  const range = (max - min) / mean * 100;
  return { min, max, mean, range };
}

// ── Main poll loop ────────────────────────────────────────────────────────────
let iteration = 0;

async function poll(horizon, rpc) {
  iteration++;
  const ts = new Date().toISOString().replace('T', ' ').slice(0, 19);

  const [cRes, sRes] = await Promise.allSettled([
    getCometData(rpc),
    getSdexData(horizon),
  ]);

  const c = cRes.status === 'fulfilled' ? cRes.value : {};
  const s = sRes.status === 'fulfilled' ? sRes.value : {};

  // Primary price: spot_price (includes fee, = actual swap cost).
  // Fallback: spot_price_sans_fee.  Balance ratio is NOT used — pool is 80/20 weighted.
  const cometPrice = c.spotPrice ?? c.spotPriceSansFee;

  pushHistory(cometPrice, s.bestBid, s.bestAsk);
  const cStat = stats(history.comet);
  const bStat = stats(history.sdexBid);

  const line = '═'.repeat(62);

  process.stdout.write('\n');
  console.log(`╔${line}╗`);
  console.log(`║  BLND/USDC Monitor  ${ts}  poll #${String(iteration).padStart(4)}         ║`);
  console.log(`╠${line}╣`);

  // Comet section
  console.log(`║  COMET AMM (LP)  [80/20 weighted pool]                       ║`);
  if (c.balances) {
    const blndStr = `${Math.round(c.balances.blnd).toLocaleString()} BLND`;
    const usdcStr = `${Math.round(c.balances.usdc).toLocaleString()} USDC`;
    console.log(row('Reserves    ', `${blndStr}  |  ${usdcStr}`));
  }
  if (c.spotPrice != null) {
    console.log(row('Spot (w/fee)', `${f(c.spotPrice)} USDC/BLND  ≈ ${(1/c.spotPrice).toFixed(2)} BLND/USDC`));
  }
  if (c.spotPriceSansFee != null) {
    console.log(row('Spot (noFee)', `${f(c.spotPriceSansFee)} USDC/BLND  ≈ ${(1/c.spotPriceSansFee).toFixed(2)} BLND/USDC`));
  }
  if (c.spotPriceErr) console.log(row('[spot err]  ', c.spotPriceErr.slice(0, 40)));
  if (c.balancesErr)  console.log(row('[bal err]   ', c.balancesErr.slice(0, 40)));

  console.log(`╠${line}╣`);

  // SDEX section
  console.log(`║  SDEX                                                         ║`);
  console.log(row('Best bid    ', `${f(s.bestBid)} USDC/BLND`, '(highest buy offer)'));
  console.log(row('Best ask    ', `${f(s.bestAsk)} USDC/BLND`, '(lowest sell offer)'));
  if (s.spread != null) {
    console.log(row('Bid/ask sprd', `${s.spread.toFixed(4)}%`));
  }
  if (s.pathSell != null) {
    console.log(row('Path sell100', `${f(s.pathSell)} USDC/BLND`, '(sell 100 BLND→USDC)'));
  }
  if (s.pathBuy != null) {
    console.log(row('Path buy 5$ ', `${s.pathBuy.toFixed(4)} BLND/USDC`, '(buy BLND w/ 5 USDC)'));
  }

  console.log(`╠${line}╣`);

  // Spread / arb section
  console.log(`║  SPREAD  (Comet spot w/fee vs SDEX)                          ║`);
  if (cometPrice != null) {
    console.log(row('vs bid      ', pctDiff(cometPrice, s.bestBid), '(+ = Comet above bid)'));
    console.log(row('vs ask      ', pctDiff(cometPrice, s.bestAsk), '(- = Comet below ask)'));
    if (s.pathSell != null) {
      console.log(row('Comet→SDEX  ', pctDiff(s.pathSell, cometPrice), '(buy Comet, sell SDEX path)'));
    }
    if (s.pathBuy != null) {
      console.log(row('SDEX→Comet  ', pctDiff(cometPrice, 1 / s.pathBuy), '(buy SDEX path, sell Comet)'));
    }
  } else {
    console.log(`║    No Comet price available                                   ║`);
  }

  // Oscillation stats (accumulate over polls)
  if (cStat && iteration > 3) {
    console.log(`╠${line}╣`);
    console.log(`║  OSCILLATION (${history.comet.length} samples)                                    ║`);
    console.log(row('Comet range ', `${f(cStat.min)}…${f(cStat.max)}`, `swing=${cStat.range.toFixed(3)}%`));
    if (bStat) {
      console.log(row('SDEX bid rng', `${f(bStat.min)}…${f(bStat.max)}`, `swing=${bStat.range.toFixed(3)}%`));
    }
  }

  console.log(`╚${line}╝`);

  if (cRes.status === 'rejected') console.error('Comet fetch error:', cRes.reason?.message);
  if (sRes.status === 'rejected') console.error('SDEX fetch error:',  sRes.reason?.message);
}

async function main() {
  const horizon = new Horizon.Server(HORIZON_URL);
  const rpc     = new SorobanRpc.Server(RPC_URL);

  console.log('BLND/USDC oscillation monitor');
  console.log(`  Comet pool : ${COMET_POOL}`);
  console.log(`  SDEX pair  : BLND:${BLND_ISSUER.slice(0,8)}… / USDC:${USDC_ISSUER.slice(0,8)}…`);
  console.log(`  Poll       : every ${POLL_MS / 1000}s  |  Ctrl-C to stop`);

  // eslint-disable-next-line no-constant-condition
  while (true) {
    try {
      await poll(horizon, rpc);
    } catch (e) {
      console.error('Poll error:', e.message);
    }
    await new Promise(r => setTimeout(r, POLL_MS));
  }
}

main();
