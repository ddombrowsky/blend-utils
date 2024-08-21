#!/bin/bash

set -e

# swap USDC -> BLND in pool

USDC_N=$1

# price is in USDC
# e.g. 0.0007
PRICE=$2

USDC=`echo $USDC_N*10000000|bc|sed -e 's/\..*//'`
MIN_OUT=`echo $USDC/$PRICE|bc|sed -e 's/\..*//'`

echo USDC=$USDC
echo MIN_OUT=$MIN_OUT

good=1
export SECRET_KEY=`stellar keys show xbull`

while [ $good = 1 ] ; do 
    soroban contract invoke \
    --id CBQDHNBFBZYE4MKPWBSJOPIYLW4SFSXAXUTSXJN76GNKYVYPCKWC6QUK \
    --source-account xbull \
    --network public --fee 10000000 -- \
    swap_chained \
    --user xbull \
    --swaps_chain '[ [ ["CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK", "CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75"], "9ac7a9cde23ac2ada11105eeaa42e43c2ea8332ca0aa8f41f58d7160274d718e", "CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK" ] ]' \
    --token_in CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75 \
    --in_amount $USDC \
    --out_min $MIN_OUT | tee out

    [ \! -s out ] && exit

    tok=`cat out`
    perl -e '
        $tok = int('$tok');
        print("buy  usdc < ".(($tok/10000000)/'$USDC_N')."\n");
        print("sell aqua > ".('$USDC_N'/($tok/10000000))."\n");
    '

    tokv=`perl -e '$tok = int('$tok');print(($tok/10000000));'`

    echo "sdex swap $tokv AQUA -> $USDC_N USDC"
    node sdex/index.js $tokv $USDC_N | tee out2
    if [ $PIPESTATUS = 0 ] ; then
        srcv=`cat out2`
    else
        srcv=0
    fi

    echo "$USDC_N < $srcv ?"
    if perl -e "$USDC_N<$srcv"'&&exit(0)||exit(1)' ; then
        echo yes, continuing
    else
        echo no, stopping
        good=0
    fi

    sleep 1
done
