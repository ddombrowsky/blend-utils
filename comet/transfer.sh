#!/bin/sh

AMT=`echo $1*10000000|bc|sed -e 's/\..*//'`
echo AMT=$AMT

DEST=GAVG3ODZ4SAVK2WJL3F3RT265RL7P6QNOMA6NL3XDAREKSX3OWWMXF4R

soroban contract invoke \
    --id CAS3FL6TLZKDGGSISDBWGGPXT3NRR4DYTZD7YOD3HMYO6LTJUVGRVEAM \
    --source-account xbull \
    --network public --fee 10000000 -- \
    transfer \
    --from xbull \
    --to $DEST \
    --amount $AMT


