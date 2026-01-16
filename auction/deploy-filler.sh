#!/bin/bash

# 1. clone the repo from
#    https://github.com/script3/interest-auction-filler.git
# 2. deploy using this script, and save the output address
# 3. use that address as the `interestFillerAddress` setting in
#    the auction bot

# owner is the _filler_ account
OWNER=G...

# This is the Backstop Smart Contract, that supports the
# backstop_token function call.  It is not specific to a pool.
# See https://docs.blend.capital/mainnet-deployments .
BACKSTOP=CAQQR5SWBXKIGZKPBZDH3KM5GQ5GUTPKB7JAFCINLZBC5WXPJKRG3IM7

# contract address for centre.io USDC
USDC_CONTRACT=CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75

NETWORK=mainnet

# NETWORK=testnet
# OWNER=G...
# BACKSTOP=CBDVWXT433PRVTUNM56C3JREF3HIZHRBA64NB2C3B2UNCKIS65ZYCLZA
# USDC_CONTRACT=CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA

make build &&
stellar contract deploy \
    --wasm ./target/wasm32v1-none/optimized/interest_auction_filler.wasm \
    --source xbull --network $NETWORK -- \
    --owner=$OWNER \
    --backstop=$BACKSTOP \
    --usdc=$USDC_CONTRACT
