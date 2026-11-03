#!/bin/bash

. ./.env

echo $PUBKEY

stellar contract invoke \
    --send=no \
    --id CDQMIKIHKA5UY3FQJ2UDTLNX3GOPD3GPNZWSPTOBVOHEUMQJQXOPC7Y3 \
    --source-account xbull \
    --network mainnet -- \
    balance \
    --id $PUBKEY | tee out

s=`cat out|sed 's/"//g'`
shares=`echo "scale=7;$s/10^7"|bc`
echo LP Shares: $shares
