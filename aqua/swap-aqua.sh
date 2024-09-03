#!/bin/bash

set -e

# swap AQUA -> USDC in pool

AQUA_N=$1

# price is in AQUA
# to get 0.0006 per AQUA, do 1/0.06 = 1666
PRICE=$2

AQUA=`echo $AQUA_N*10000000|bc|sed -e 's/\..*//'`
MIN_OUT=`echo $AQUA/$PRICE|bc|sed -e 's/\..*//'`

echo AQUA=$AQUA
echo MIN_OUT=$MIN_OUT

good=1
export SECRET_KEY=`stellar keys show xbull`

#    XLM/AQUA -> USDC/AQUA
#CHAIN='[ [ ["CAS3J7GYLGXMF6TDJBBYYSE3HQ6BBSMLNUQ34T6TZMYMW2EVH34XOWMA", "CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK"], "b2e02fcfca6c96f8ad5cbd84e7784a777b36d9c96a2459402c4f458462aab7f0", "CAS3J7GYLGXMF6TDJBBYYSE3HQ6BBSMLNUQ34T6TZMYMW2EVH34XOWMA" ], [ ["CAS3J7GYLGXMF6TDJBBYYSE3HQ6BBSMLNUQ34T6TZMYMW2EVH34XOWMA", "CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75"], "b2e02fcfca6c96f8ad5cbd84e7784a777b36d9c96a2459402c4f458462aab7f0", "CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75" ] ]'

#   USDC/AQUA
CHAIN='[ [ ["CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK", "CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75"], "9ac7a9cde23ac2ada11105eeaa42e43c2ea8332ca0aa8f41f58d7160274d718e", "CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75" ] ]'

while [ $good = 1 ] ; do 
    soroban contract invoke \
    --id CBQDHNBFBZYE4MKPWBSJOPIYLW4SFSXAXUTSXJN76GNKYVYPCKWC6QUK \
    --source-account xbull \
    --network public --fee 10000000 -- \
    swap_chained \
    --user xbull \
    --swaps_chain "$CHAIN" \
    --token_in CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK \
    --in_amount $AQUA \
    --out_min $MIN_OUT | tee out

    [ \! -s out ] && exit

    tok=`cat out`
    perl -e '
        $tok = int('$tok');
        print("sell usdc > ".('$AQUA_N'/($tok/10000000))."\n");
        print("buy  aqua < ".(($tok/10000000)/'$AQUA_N')."\n");
    '

    tokv=`perl -e '$tok = int('$tok');print(($tok/10000000));'`

    echo "sdex swap $tokv USDC -> $AQUA_N AQUA"
    sleep 2
    node sdex/index.js $tokv $AQUA_N inverse | tee out2
    if [ $PIPESTATUS = 0 ] ; then
        srcv=`cat out2`
    else
        srcv=0
    fi

    echo "$AQUA_N+7 < $srcv ?"
    if perl -e "($AQUA_N+7)<$srcv"'&&exit(0)||exit(1)' ; then
        echo yes, continuing
    else
        echo no, stopping
        good=0
    fi

    sleep 2
done
