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

#   XLM/USDC -> XLM/AQUA
#    --swaps_chain '[ [ ["CAS3J7GYLGXMF6TDJBBYYSE3HQ6BBSMLNUQ34T6TZMYMW2EVH34XOWMA", "CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75"], "b2e02fcfca6c96f8ad5cbd84e7784a777b36d9c96a2459402c4f458462aab7f0", "CAS3J7GYLGXMF6TDJBBYYSE3HQ6BBSMLNUQ34T6TZMYMW2EVH34XOWMA" ], [ ["CAS3J7GYLGXMF6TDJBBYYSE3HQ6BBSMLNUQ34T6TZMYMW2EVH34XOWMA", "CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK"], "b2e02fcfca6c96f8ad5cbd84e7784a777b36d9c96a2459402c4f458462aab7f0", "CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK" ] ]' \

#   USDC/AQUA
#    --swaps_chain '[ [ ["CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK", "CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75"], "9ac7a9cde23ac2ada11105eeaa42e43c2ea8332ca0aa8f41f58d7160274d718e", "CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK" ] ]' \

    [ \! -s out ] && exit

    tok=`cat out`
    perl -e '
        $tok = int('$tok');
        print("buy  usdc < ".(($tok/10000000)/'$USDC_N')."\n");
        print("sell aqua > ".('$USDC_N'/($tok/10000000))."\n");
    '

    tokv=`perl -e '$tok = int('$tok');print(($tok/10000000));'`

    echo "sdex swap $tokv AQUA -> $USDC_N USDC"
    sleep 2
    node sdex/index.js $tokv $USDC_N | tee out2
    if [ $PIPESTATUS = 0 ] ; then
        srcv=`cat out2`
    else
        srcv=0
    fi

    echo "$USDC_N+0.1 < $srcv ?"
    if perl -e "($USDC_N+0.1)<$srcv"'&&exit(0)||exit(1)' ; then
        echo yes, continuing
    else
        echo no, stopping
        good=0
    fi

    sleep 2
done
