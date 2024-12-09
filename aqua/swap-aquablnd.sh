#!/bin/bash
set -e

# swap AQUA -> BLND in pool
AQUA_N=$1
# price is in AQUA
PRICE=$2

# in AQUA
FEEMARGIN=5

AQUA=`echo $AQUA_N*10000000|bc|sed -e 's/\..*//'`
MIN_OUT=`echo $AQUA/$PRICE|bc|sed -e 's/\..*//'`

echo AQUA=$AQUA
echo MIN_OUT=$MIN_OUT
echo FEEMARGIN=$FEEMARGIN

good=1
export SECRET_KEY=`stellar keys show xbull`

#    BLND/AQUA
# 0.30%
CHAIN='[ [ ["CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK", "CD25MNVTZDL4Y3XBCPCJXGXATV5WUHHOWMYFF4YBEGU5FCPGMYTVG5JY"], "9ac7a9cde23ac2ada11105eeaa42e43c2ea8332ca0aa8f41f58d7160274d718e", "CD25MNVTZDL4Y3XBCPCJXGXATV5WUHHOWMYFF4YBEGU5FCPGMYTVG5JY" ] ]'

TOKSTR=AQUA
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
        $an = '$AQUA_N'+'$FEEMARGIN';
        print("sell blnd > ".($an/($tok/10000000))."\n");
        print("buy '$TOKSTR' < ".(($tok/10000000)/$an)."\n");
    '

    tokv=`perl -e '$tok = int('$tok');print(($tok/10000000));'`

    echo "sdex swap $tokv BLND -> $AQUA_N+$FEEMARGIN $TOKSTR"
    sleep 3
    node sdex/index-blndaqua.js $tokv `echo $AQUA_N+$FEEMARGIN|bc` inverse | tee out2
    if [ $PIPESTATUS = 0 ] ; then
        srcv=`cat out2`
    else
        srcv=0
    fi

    echo "$AQUA_N+$FEEMARGIN < $srcv ?"
    if perl -e "($AQUA_N+$FEEMARGIN)<$srcv"'&&exit(0)||exit(1)' ; then
        echo yes, continuing
    else
        echo no, stopping
        good=0
    fi

    # press ENTER to exit
    read -t 1 foo && exit
    sleep 2
done
