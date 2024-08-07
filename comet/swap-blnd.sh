#!/bin/bash

set -e

# swap BLND -> USDC

# NOTE: error #22 = bad limit price

# PRICE is in BLND.
# To get 0.078 per BLND, do 1/0.078=12.82
if [ -z "$2" ] ; then
    PRICE=13.70
else
    PRICE=$2
fi

BLND_N=$1

BLND=`echo $BLND_N*10000000|bc|sed -e 's/\..*//'`
PRICESTR=`echo $PRICE*10000000|bc|sed -e 's/\..*//'`

echo BLND=$BLND
echo PRICE=$PRICESTR

soroban contract invoke \
--id CAS3FL6TLZKDGGSISDBWGGPXT3NRR4DYTZD7YOD3HMYO6LTJUVGRVEAM \
--source-account xbull \
--network public --fee 10000000 -- \
swap_exact_amount_in \
--token_in CD25MNVTZDL4Y3XBCPCJXGXATV5WUHHOWMYFF4YBEGU5FCPGMYTVG5JY \
--token_amount_in $BLND \
--token_out CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75 \
--min_amount_out 1 \
--max_price $PRICESTR \
--user xbull | tee out

[ \! -s out ] && exit

tok=`jq .[0] out`
perl -e '
    $tok = int('$tok');
    print("sell usdc > ".('$BLND_N'/($tok/10000000))."\n");
    print("buy  blnd < ".(($tok/10000000)/'$BLND_N')."\n");
'
