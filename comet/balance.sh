#!/bin/sh

PUBKEY=$1

echo $PUBKEY

soroban contract invoke \
    --id CAS3FL6TLZKDGGSISDBWGGPXT3NRR4DYTZD7YOD3HMYO6LTJUVGRVEAM \
    --source-account xbull \
    --network public -- \
    balance \
    --id $PUBKEY | tee out

s=`cat out|sed 's/"//g'`
shares=`echo "scale=7;$s/10^7"|bc`
echo LP Shares: $shares
