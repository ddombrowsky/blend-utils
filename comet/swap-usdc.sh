#!/bin/bash
set -e

# swap USDC -> BLND in pool
USDC_N=$1
# price is in USDC
# e.g. 0.04, = bottom sell price in orderbook
PRICE=$2

# in USDC
FEEMARGIN=0.005

USDC=`echo $USDC_N*10000000|bc|sed -e 's/\..*//'`
PRICESTR=`echo $PRICE*10000000|bc|sed -e 's/\..*//'`

echo USDC=$USDC
echo PRICE=$PRICESTR
echo FEEMARGIN=$FEEMARGIN

good=1
export SECRET_KEY=`stellar keys show xbull`

TOKSTR=BLND
while [ $good = 1 ] ; do 
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
        print("sell '$TOKSTR' > ".(('$USDC_N'+'$FEEMARGIN')/($tok/10000000))."\n");
    '

    tokv=`perl -e '$tok = int('$tok');print(($tok/10000000));'`

    echo "sdex swap $tokv $TOKSTR -> $USDC_N+$FEEMARGIN USDC"
    sleep 3
    node sdex/index.js $tokv `echo $USDC_N+$FEEMARGIN|bc` | tee out2
    if [ $PIPESTATUS = 0 ] ; then
        srcv=`cat out2`
    else
        srcv=0
    fi

    echo "$USDC_N+$FEEMARGIN < $srcv ?"
    if perl -e "($USDC_N+$FEEMARGIN)<$srcv"'&&exit(0)||exit(1)' ; then
        echo yes, continuing
    else
        echo no, stopping
        good=0
    fi

    # press ENTER to exit
    read -t 1 foo && exit
    sleep 2
done
