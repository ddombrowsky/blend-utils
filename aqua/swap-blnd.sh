#!/bin/bash
set -e

# swap BLND -> AQUA in pool
BLND_N=$1
# price is in BLND
# to get 0.0006 per BLND, do 1/0.06 = 1666, = bottom sell price in orderbook
PRICE=$2

# in BLND
FEEMARGIN=0.15

BLND=`echo $BLND_N*10000000|bc|sed -e 's/\..*//'`
MIN_OUT=`echo $BLND/$PRICE|bc|sed -e 's/\..*//'`

echo BLND=$BLND
echo MIN_OUT=$MIN_OUT
echo FEEMARGIN=$FEEMARGIN

good=1
export SECRET_KEY=`stellar keys show xbull`

#    BLND/AQUA
# 0.30%
#CHAIN='[ [ ["CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK", "CD25MNVTZDL4Y3XBCPCJXGXATV5WUHHOWMYFF4YBEGU5FCPGMYTVG5JY"], "9ac7a9cde23ac2ada11105eeaa42e43c2ea8332ca0aa8f41f58d7160274d718e", "CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK" ] ]'

TOKSTR=BLND
while [ $good = 1 ] ; do
    node sdex/findpath.js \
      CD25MNVTZDL4Y3XBCPCJXGXATV5WUHHOWMYFF4YBEGU5FCPGMYTVG5JY \
      CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK \
      $BLND $MIN_OUT | tee out

    [ \! -s out ] && exit

    tok=`cat out`
    perl -e '
        $tok = int('$tok');
        $an = '$BLND_N'+'$FEEMARGIN';
        print("sell usdc > ".($an/($tok/10000000))."\n");
        print("buy '$TOKSTR' < ".(($tok/10000000)/$an)."\n");
    '

    tokv=`perl -e '$tok = int('$tok');print(($tok/10000000));'`

    echo "sdex swap $tokv AQUA -> $BLND_N+$FEEMARGIN $TOKSTR"
    sleep 3
    node sdex/index-blndaqua.js $tokv `echo $BLND_N+$FEEMARGIN|bc` | tee out2
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

    # press ENTER to exit
    read -t 1 foo && exit
    sleep 2
done
