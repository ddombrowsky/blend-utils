# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A collection of scripts and utilities for interacting with the [Blend protocol](https://www.blend.capital/) on the Stellar/Soroban network. Also includes some AQUA-related scripts. All on-chain amounts use 7 decimal fixed-point (multiply by 10^7 to get the integer representation used by contracts).

## Repository Structure

- **`comet/`** — Scripts for the Comet AMM (BLND/USDC liquidity pool). The pool contract is `CAS3FL6TLZKDGGSISDBWGGPXT3NRR4DYTZD7YOD3HMYO6LTJUVGRVEAM`.
- **`comet/sdex/`** — Node.js scripts for SDEX (Stellar DEX) operations (path payments and sell offers).
- **`aqua/`** — Same swap-bot pattern as `comet/` but for the AQUA protocol.
- **`balances/`** — TypeScript program that reads Blend pool positions and backstop balances for a given wallet.
- **`gov/`** — TypeScript script for voting on Blend governance proposals via the soroban-governor SDK.
- **`auction/`** — Config and startup scripts for running the `script3/auctioneer-bot` Docker container (liquidation/interest auction bot).

## Key Contracts (Mainnet)

| Name | Address |
|------|---------|
| Comet pool (BLND/USDC) | `CAS3FL6TLZKDGGSISDBWGGPXT3NRR4DYTZD7YOD3HMYO6LTJUVGRVEAM` |
| BLND token | `CD25MNVTZDL4Y3XBCPCJXGXATV5WUHHOWMYFF4YBEGU5FCPGMYTVG5JY` |
| USDC token | `CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75` |
| Backstop v1 | `CAO3AGAMZVRMHITL36EJ2VZQWKYRPWMQAPDQD5YEOF3GIF7T44U4JAL3` |
| Backstop v2 | `CAQQR5SWBXKIGZKPBZDH3KM5GQ5GUTPKB7JAFCINLZBC5WXPJKRG3IM7` |
| Governor | `CANSYFVMIP7JVYEZQ463Y2I2VLEVNLDJJ4QNZTDBGLOOGKURPTW4A6FQ` |

## Prerequisites

- `stellar` CLI (formerly `soroban`) with a key named `xbull` configured: `stellar keys add xbull --secret-key`
- Network configured: `soroban network add public --rpc-url https://soroban-rpc.creit.tech --network-passphrase 'Public Global Stellar Network ; September 2015'`
- Node.js (for `sdex/`, `balances/`, `gov/`)
- `jq`, `bc`, `perl` (for the shell swap scripts)
- `SECRET_KEY` env var must be set for Node.js scripts (the shell scripts export it from `stellar keys show xbull`)

## Commands

### comet/ — Swap scripts

```sh
# Swap USDC → BLND; args: amount_in_USDC, max_price_in_USDC_per_BLND
./swap-usdc.sh 5 0.069

# Swap BLND → USDC; args: amount_in_BLND, max_price_in_BLND_per_USDC
./swap-blnd.sh 200 16.1

# Check LP share balance for a wallet
./balance.sh [PUBKEY]

# Transfer Comet LP tokens
./transfer.sh <amount>
```

The swap scripts loop: first swap on Comet AMM, then attempt to arbitrage back via SDEX. Press Enter to exit the loop.

### comet/sdex/ — SDEX scripts

```sh
cd comet/sdex && npm install

# Path-payment BLND→USDC (or USDC→BLND with "inverse")
node index.js <source_amount> <dest_min_amount> [inverse]

# Place a limit sell offer on the SDEX
node sell.js <sell_issue> <sell_code> <buy_issue> <buy_code> <sell_amt> <price>
```

### balances/ — Pool position reader

```sh
cd balances
npx tsc          # build (outputs to dist/)
# or: make

node dist/index.js <PUBKEY> [PUBKEY2 ...]
# or: ./run.sh
```

### gov/ — Governance voting

Configure network via env vars `NEXT_PUBLIC_RPC_URL` / `NEXT_PUBLIC_PASSPHRASE` (defaults to testnet). Set `SECRET_KEY` for signing.

```sh
cd gov && npm install
npx tsc
node dist/index.js
```

The `vote()` call at the bottom of `index.ts` is edited directly to set `proposalId` and `support` (0=against, 1=for, 2=abstain).

### auction/ — Auctioneer bot

The bot runs as Docker containers. Config JSON goes in `data/`, `data-ybx/`, etc.

```sh
cd auction

# Start all bots (see start.sh for individual containers)
sh start.sh

# Tail logs
sh tail.sh

# Run a local Stellar Core RPC node (reduces rate-limiting)
sh startrpc.sh
```

Key config fields in `data/config.json`: `workerKeypair`, `fillerKeypair`, `interestFillerAddress`, `minHealthFactor`, `defaultProfitPct`.
