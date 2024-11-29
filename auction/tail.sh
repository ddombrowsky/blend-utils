#!/bin/sh

F=$1

file1=`/bin/ls -1t data/logs/main* |head -1`
file2=`/bin/ls -1t data-ybx/logs/main* |head -1`

#tail -n 1000 $F $file |
#    grep 'Processing pool event' |
#    jq .message |
#    perl -ne 's/Processing pool event: //; print eval("$_")."\n"' |
#    jq .

tail -q -n 1000 $F $file1 $file2

echo '= trades ='
echo fixed:
sqlite3 data/auctioneer.sqlite  'select timestamp, tx_hash, auction_type, bid_total, est_profit from filled_auctions;'
echo ybx:
sqlite3 data-ybx/auctioneer.sqlite  'select timestamp, tx_hash, auction_type, bid_total, est_profit from filled_auctions;'
