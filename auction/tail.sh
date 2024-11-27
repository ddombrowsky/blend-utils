#!/bin/sh

F=$1

file=`/bin/ls -1t data/logs/main* |head -1`

#tail -n 1000 $F $file |
#    grep 'Processing pool event' |
#    jq .message |
#    perl -ne 's/Processing pool event: //; print eval("$_")."\n"' |
#    jq .
tail -n 1000 $F $file |
    grep -v ERR_BAD_RESPONSE | 
    jq .

sqlite3 data/auctioneer.sqlite  'select timestamp, tx_hash, auction_type, bid_total, est_profit from filled_auctions;'
