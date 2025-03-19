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

AQUA_ISSUE=GBNZILSTVQZ4R7IKQDGHYGY2QXL5QOFJYQMXPKWRRM5PAV7Y4M67AQUA
AQUA_CODE=AQUA
AQUA_CONTRACT=CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK
BLND_ISSUE=GDJEHTBE6ZHUXSWFI642DCGLUOECLHPF3KSXHPXTSTJ7E3JF6MQ5EZYY
BLND_CODE=BLND
BLND_CONTRACT=CD25MNVTZDL4Y3XBCPCJXGXATV5WUHHOWMYFF4YBEGU5FCPGMYTVG5JY

echo AQUA=$AQUA
echo MIN_OUT=$MIN_OUT
echo FEEMARGIN=$FEEMARGIN

good=1
export SECRET_KEY=`stellar keys show xbull`

TOKSTR=AQUA
while [ $good = 1 ] ; do
    node sdex/findpath.js \
      $AQUA_CONTRACT \
      $BLND_CONTRACT \
      $AQUA $MIN_OUT | tee out

    [ \! -s out ] && exit

    tok=`cat out`
    perl -e '
        $tok = int('$tok');
        $an = '$AQUA_N'+'$FEEMARGIN';
        print("sell blnd > ".($an/($tok/10000000))."\n");
        print("buy '$TOKSTR' < ".(($tok/10000000)/$an)."\n");
    '

    tokv=`perl -e '$tok = int('$tok');print(($tok/10000000));'`
    pricev=`perl -e '
        $tok = int('$tok');
        printf("%0.7f",(('$AQUA_N'+'$FEEMARGIN')*1.0001)/($tok/10000000));'`
    buytokv=`echo $AQUA_N+$FEEMARGIN|bc`

    echo "sdex swap $tokv BLND -> $AQUA_N+$FEEMARGIN $TOKSTR"
    sleep 3
    node sdex/index-blndaqua.js $tokv $buytokv inverse | tee out2
    if [ $PIPESTATUS = 0 ] ; then
        srcv=`cat out2`
    else
        srcv=0
    fi

    # press ENTER to exit
    read -t 1 foo && exit

    echo "$AQUA_N+$FEEMARGIN < $srcv ?"
    if perl -e "($AQUA_N+$FEEMARGIN)<$srcv"'&&exit(0)||exit(1)' ; then
        echo yes, continuing
    else
        echo no, placing order @ $pricev
        node sdex/sell.js $BLND_ISSUE $BLND_CODE $AQUA_ISSUE $AQUA_CODE \
            $tokv $pricev
        good=0
    fi

    sleep 2
done
