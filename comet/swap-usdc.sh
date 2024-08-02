#!/bin/bash

set -e

# swap USDC -> BLND

# PRICE is in USDC
if [ -z "$2" ] ; then
    PRICE=0.071
else
    PRICE=$2
fi

USDC_N=$1

USDC=`echo $USDC_N*10000000|bc|sed -e 's/\..*//'`
PRICESTR=`echo $PRICE*10000000|bc|sed -e 's/\..*//'`

echo USDC=$USDC
echo PRICE=$PRICESTR

soroban contract invoke \
--id CAS3FL6TLZKDGGSISDBWGGPXT3NRR4DYTZD7YOD3HMYO6LTJUVGRVEAM \
--source-account xbull \
--network public --fee 10000000 -- \
swap_exact_amount_in \
--token_in CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75 \
--token_amount_in $USDC \
--token_out CD25MNVTZDL4Y3XBCPCJXGXATV5WUHHOWMYFF4YBEGU5FCPGMYTVG5JY \
--min_amount_out 1 \
--max_price $PRICESTR \
--user xbull | tee out

[ \! -s out ] && exit

tok=`jq .[0] out`
perl -e '
    $tok = int('$tok');
    print("buy  usdc < ".(($tok/10000000)/'$USDC_N')."\n");
    print("sell blnd > ".('$USDC_N'/($tok/10000000))."\n");
'
