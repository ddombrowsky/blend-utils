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

AQUA_ISSUE=GBNZILSTVQZ4R7IKQDGHYGY2QXL5QOFJYQMXPKWRRM5PAV7Y4M67AQUA
AQUA_CODE=AQUA
AQUA_CONTRACT=CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK
BLND_ISSUE=GDJEHTBE6ZHUXSWFI642DCGLUOECLHPF3KSXHPXTSTJ7E3JF6MQ5EZYY
BLND_CODE=BLND
BLND_CONTRACT=CD25MNVTZDL4Y3XBCPCJXGXATV5WUHHOWMYFF4YBEGU5FCPGMYTVG5JY 

echo BLND=$BLND
echo MIN_OUT=$MIN_OUT
echo FEEMARGIN=$FEEMARGIN

good=1
export SECRET_KEY=`stellar keys show xbull`

TOKSTR=BLND
while [ $good = 1 ] ; do
    node sdex/findpath.js \
      $BLND_CONTRACT \
      $AQUA_CONTRACT \
      $BLND $MIN_OUT | tee out

    [ \! -s out ] && exit

    tok=`cat out`
    perl -e '
        $tok = int('$tok');
        $an = '$BLND_N'+'$FEEMARGIN';
        print("sell aqua > ".($an/($tok/10000000))."\n");
        print("buy '$TOKSTR' < ".(($tok/10000000)/$an)."\n");
    '

    tokv=`perl -e '$tok = int('$tok');print(($tok/10000000));'`
    pricev=`perl -e '
        $tok = int('$tok');
        printf("%0.7f",(('$BLND_N'+'$FEEMARGIN')*1.0001)/($tok/10000000));'`
    buytokv=`echo $BLND_N+$FEEMARGIN|bc`

    echo "sdex swap $tokv AQUA -> $BLND_N+$FEEMARGIN $TOKSTR"
    sleep 3
    node sdex/index-blndaqua.js $tokv `echo $BLND_N+$FEEMARGIN|bc` | tee out2
    if [ $PIPESTATUS = 0 ] ; then
        srcv=`cat out2`
    else
        srcv=0
    fi

    # press ENTER to exit
    read -t 1 foo && exit

    echo "$BLND_N+$FEEMARGIN < $srcv ?"
    if perl -e "($BLND_N+$FEEMARGIN)<$srcv"'&&exit(0)||exit(1)' ; then
        echo yes, continuing
    else
        echo no, placing order @ $pricev
        node sdex/sell.js $AQUA_ISSUE $AQUA_CODE $BLND_ISSUE $BLND_CODE \
            $tokv $pricev
        good=0
    fi

    sleep 2
done
