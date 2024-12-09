#!/bin/sh

# error 1215 = interest too small

soroban contract invoke \
    --id CDE65QK2ROZ32V2LVLBOKYPX47TYMYO37Z6ASQTBRTBNK53C7C6QF4Y7 \
    --source-account xbull \
    --network public --fee 10000000 -- \
    new_interest_auction \
    --assets '["CAS3J7GYLGXMF6TDJBBYYSE3HQ6BBSMLNUQ34T6TZMYMW2EVH34XOWMA","CDIKURWHYS4FFTR5KOQK6MBFZA2K3E26WGBQI6PXBYWZ4XIOPJHDFJKP","CBN3NCJSMOQTC6SPEYK3A44NU4VS3IPKTARJLI3Y77OH27EWBY36TP7U","CBCO65UOWXY2GR66GOCMCN6IU3Y45TXCPBY3FLUNL4AOUMOCKVIVV6JC"]'