#!/bin/bash
set -e

# swap AQUA -> USDC in pool
AQUA_N=$1
# price is in AQUA
# to get 0.0006 per AQUA, do 1/0.06 = 1666, = bottom sell price in orderbook
PRICE=$2

# in AQUA
FEEMARGIN=7

AQUA=`echo $AQUA_N*10000000|bc|sed -e 's/\..*//'`
MIN_OUT=`echo $AQUA/$PRICE|bc|sed -e 's/\..*//'`

echo AQUA=$AQUA
echo MIN_OUT=$MIN_OUT
echo FEEMARGIN=$FEEMARGIN

good=1
export SECRET_KEY=`stellar keys show xbull`

TOKSTR=AQUA
while [ $good = 1 ] ; do 
    node sdex/findpath.js \
      CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK \
      CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75 \
      $AQUA $MIN_OUT | tee out

    [ \! -s out ] && exit

    tok=`cat out`
    perl -e '
        $tok = int('$tok');
        $an = '$AQUA_N'+'$FEEMARGIN';
        print("sell usdc > ".($an/($tok/10000000))."\n");
        print("buy '$TOKSTR' < ".(($tok/10000000)/$an)."\n");
    '

    tokv=`perl -e '$tok = int('$tok');print(($tok/10000000));'`

    echo "sdex swap $tokv USDC -> $AQUA_N+$FEEMARGIN $TOKSTR"
    sleep 3
    node sdex/index.js $tokv `echo $AQUA_N+$FEEMARGIN|bc` inverse | tee out2
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
