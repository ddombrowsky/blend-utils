#!/bin/bash
set -e

# swap BLND -> USDC in pool
BLND_N=$1
# price is in BLND.
# To get 0.078 per BLND, do 1/0.078=12.82, = bottom sell price in orderbook
PRICE=$2

# in BLND
FEEMARGIN=0.04

BLND=`echo $BLND_N*10000000|bc|sed -e 's/\..*//'`
PRICESTR=`echo $PRICE*10000000|bc|sed -e 's/\..*//'`

echo BLND=$BLND
echo PRICE=$PRICESTR
echo FEEMARGIN=$FEEMARGIN

good=1
export SECRET_KEY=`stellar keys show xbull`

TOKSTR=BLND
while [ $good = 1 ] ; do 
    # NOTE: error #22 = bad limit price
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
        print("buy '$TOKSTR' < ".(($tok/10000000)/('$BLND_N'+'$FEEMARGIN'))."\n");
    '

    tokv=`perl -e '$tok = int('$tok');print(($tok/10000000));'`

    echo "sdex swap $tokv USDC -> $BLND_N+$FEEMARGIN $TOKSTR"
    sleep 3
    node sdex/index.js $tokv `echo $BLND_N+$FEEMARGIN|bc` inverse | tee out2
    if [ $PIPESTATUS = 0 ] ; then
        srcv=`cat out2`
    else
        srcv=0
    fi

    echo "$BLND_N+$FEEMARGIN < $srcv ?"
    if perl -e "($BLND_N+$FEEMARGIN)<$srcv"'&&exit(0)||exit(1)' ; then
        echo yes, continuing
    else
        echo no, stopping
        good=0
    fi

    sleep 2
done
