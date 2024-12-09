#!/bin/sh

URL='https://amm-api.aqua.network/api/external/v1'

TIN=CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK  # aqua
TOUT=CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75 # usdc
AMT=10000000

curl -XPOST --header "Content-Type:application/json" -d "{ "\
"\"token_in_address\":\"$TIN\","\
"\"token_out_address\":\"$TOUT\","\
"\"amount\":$AMT "\
"}" "$URL/find-path/"

