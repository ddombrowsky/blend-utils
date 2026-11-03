#!/bin/bash

. ./.env

echo $PUBKEY

stellar contract invoke \
    --send=no \
    --id CDQMIKIHKA5UY3FQJ2UDTLNX3GOPD3GPNZWSPTOBVOHEUMQJQXOPC7Y3 \
    --source-account xbull \
    --network mainnet -- \
    balance \
    --id $PUBKEY | tee out

s=`cat out|sed 's/"//g'`
shares=`echo "scale=7;$s/10^7"|bc`
echo LP Shares: $shares

# -- Swap rates on the BLNT/USDC Comet pool --
# Computed from pool state (balances, weights, swap fee) with the Balancer
# out-given-in formula, so it needs no wallet balance:
#   out = Bo * (1 - (Bi / (Bi + Ai*(1-fee)))^(wi/wo))
POOL=CDQMIKIHKA5UY3FQJ2UDTLNX3GOPD3GPNZWSPTOBVOHEUMQJQXOPC7Y3
BLNT=CCBNWP5L7ZSXA3DBWCMFAVKFVRW3ZHWO7B5J557W42O64DDZNPJP7VDS
USDC=CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75

view() {
    stellar contract invoke --id $POOL --source-account xbull \
        --network mainnet --send no -- "$@" | tail -1 | sed 's/"//g'
}

FEE=`view get_swap_fee`
BAL_BLNT=`view get_balance --token $BLNT`
BAL_USDC=`view get_balance --token $USDC`
W_BLNT=`view get_normalized_weight --token $BLNT`
W_USDC=`view get_normalized_weight --token $USDC`

# out_given_in Bi wi Bo wo Ai   (all in 7-decimal integer units except Ai)
out_given_in() {
    echo "scale=20; f=$FEE/10^7; bi=$1/10^7; bo=$3/10^7; r=$2/$4;
          x=bi/(bi+$5*(1-f)); o=bo*(1-e(r*l(x))); scale=7; o/1" | bc -l | sed "s/^\./0./"
}

U2B=`out_given_in $BAL_USDC $W_USDC $BAL_BLNT $W_BLNT 1`
B2U=`out_given_in $BAL_BLNT $W_BLNT $BAL_USDC $W_USDC 1`

echo "Pool: `echo "scale=7;$BAL_BLNT/10^7"|bc` BLNT / `echo "scale=7;$BAL_USDC/10^7"|bc` USDC, fee `echo "scale=4;$FEE/10^5"|bc`%"
echo "1 USDC -> $U2B BLNT"
echo "1 BLNT -> $B2U USDC"
