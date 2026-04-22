#!/bin/sh

AMT=`echo $1*10000000|bc|sed -e 's/\..*//'`
echo AMT=$AMT

DEST=GBE4FY6RLT4KYM35MR47ZXATCG67ONZ7VKESEMHFPF2QF3VVHV2QM6L2

stellar contract invoke \
    --id CAS3FL6TLZKDGGSISDBWGGPXT3NRR4DYTZD7YOD3HMYO6LTJUVGRVEAM \
    --source-account xbull \
    --network mainnet --fee 10000000 -- \
    transfer \
    --from xbull \
    --to $DEST \
    --amount $AMT


