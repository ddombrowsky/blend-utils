#!/bin/bash
set -e

# swap USDC -> BLNT in pool
USDC_N=$1
# price is in USDC
# e.g. 0.04, = bottom sell price in orderbook
PRICE=$2

# in USDC
FEEMARGIN=0.012

USDC=`echo $USDC_N*10000000|bc|sed -e 's/\..*//'`
PRICESTR=`echo $PRICE*10000000|bc|sed -e 's/\..*//'`

BLNT_ISSUE=GAP2ACGH3O6TRFAERGM4USJ6XWU3U2BFIK224JPV6NI3CUNEEEGTBTFB
BLNT_CODE=BLNT
BLNT_CONTRACT=CCBNWP5L7ZSXA3DBWCMFAVKFVRW3ZHWO7B5J557W42O64DDZNPJP7VDS
USDC_ISSUE=GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN
USDC_CODE=USDC
USDC_CONTRACT=CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75

echo USDC=$USDC
echo PRICE=$PRICESTR
echo FEEMARGIN=$FEEMARGIN

good=1
export SECRET_KEY=`stellar keys show xbull`

TOKSTR=BLNT
while [ $good = 1 ] ; do
    stellar contract invoke \
    --id CDQMIKIHKA5UY3FQJ2UDTLNX3GOPD3GPNZWSPTOBVOHEUMQJQXOPC7Y3 \
    --source-account xbull \
    --network mainnet --inclusion-fee 10000000 -- \
    swap_exact_amount_in \
    --token_in $USDC_CONTRACT \
    --token_amount_in $USDC \
    --token_out $BLNT_CONTRACT \
    --min_amount_out 1 \
    --max_price $PRICESTR \
    --user xbull | tee out

    [ \! -s out ] && exit 1

    tok=`jq .[0] out`
    perl -e '
        $tok = int('$tok');
        $un = '$USDC_N'+'$FEEMARGIN';
        print("buy  usdc < ".(($tok/10000000)/$un)."\n");
        print("sell '$TOKSTR' > ".($un/($tok/10000000))."\n");
    '

    tokv=`perl -e '$tok = int('$tok');print(($tok/10000000));'`
    pricev=`perl -e '
        $tok = int('$tok');
        printf("%0.7f",(('$USDC_N'+'$FEEMARGIN')*1.0001)/($tok/10000000));'`
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
        node sdex/sell.js $BLNT_ISSUE $BLNT_CODE $USDC_ISSUE $USDC_CODE \
            $tokv $pricev
        good=0
    fi

    sleep 2
done
