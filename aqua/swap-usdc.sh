#!/bin/bash
set -e

# swap USDC -> BLND in pool
USDC_N=$1
# price is in USDC
# e.g. 0.00061, = bottom sell price in orderbook
PRICE=$2

# in USDC
FEEMARGIN=0.028

USDC=`echo $USDC_N*10000000|bc|sed -e 's/\..*//'`
MIN_OUT=`echo $USDC/$PRICE|bc|sed -e 's/\..*//'`

AQUA_ISSUE=GBNZILSTVQZ4R7IKQDGHYGY2QXL5QOFJYQMXPKWRRM5PAV7Y4M67AQUA
AQUA_CODE=AQUA
AQUA_CONTRACT=CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK
USDC_ISSUE=GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN
USDC_CODE=USDC
USDC_CONTRACT=CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75

echo USDC=$USDC
echo MIN_OUT=$MIN_OUT
echo FEEMARGIN=$FEEMARGIN

good=1
export SECRET_KEY=`stellar keys show xbull`

TOKSTR=AQUA
while [ $good = 1 ] ; do
    node sdex/findpath.js \
      $USDC_CONTRACT \
      $AQUA_CONTRACT \
      $USDC $MIN_OUT | tee out

    [ \! -s out ] && exit 1

    tok=`cat out`
    perl -e '
        $tok = int('$tok');
        $un = '$USDC_N'+'$FEEMARGIN';
        print("buy  usdc < ".(($tok/10000000)/$un)."\n");
        print("sell '$TOKSTR' > ".($un/($tok/10000000))."\n");
    '

    tokv=`perl -e '$tok = int('$tok');print(($tok/10000000));'`
    pricev=`perl -e '
        $tok = int('$tok');
        printf("%0.7f",(('$USDC_N'+'$FEEMARGIN')*1.003)/($tok/10000000));'`
    buytokv=`echo $USDC_N+$FEEMARGIN|bc`

    echo "sdex swap $tokv $TOKSTR -> $USDC_N+$FEEMARGIN USDC"
    sleep 3
    node sdex/index.js $tokv $buytokv | tee out2
    if [ $PIPESTATUS = 0 ] ; then
        srcv=`cat out2`
    else
        srcv=0
    fi

    # press ENTER to exit
    read -t 1 foo && exit

    echo "$USDC_N+$FEEMARGIN < $srcv ?"
    if perl -e "($USDC_N+$FEEMARGIN)<$srcv"'&&exit(0)||exit(1)' ; then
        echo yes, continuing
    else
        echo no, placing order @ $pricev
        node sdex/sell.js $AQUA_ISSUE $AQUA_CODE $USDC_ISSUE $USDC_CODE \
            $tokv $pricev
        good=0
    fi

    sleep 2
done
