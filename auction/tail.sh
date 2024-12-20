#!/bin/sh

F=$1

file1=`/bin/ls -1t data/logs/main* |head -1`
file2=`/bin/ls -1t data-ybx/logs/main* |head -1`
file3=`/bin/ls -1t data-fxdao/logs/main* |head -1`

#tail -n 1000 $F $file |
#    grep 'Processing pool event' |
#    jq .message |
#    perl -ne 's/Processing pool event: //; print eval("$_")."\n"' |
#    jq .

#tail -q -n 10 $F $file1 $file2 $file3 | jq .
if [ -n "$1" ] ; then
    echo $file1
    tail -n 2 $file1 | jq .
    echo $file2
    tail -n 2 $file2 | jq .
    echo $file3
    tail -n 2 $file3 | jq .
    exit
fi

echo '= trades ='
echo fixed:
sqlite3 data/auctioneer.sqlite  'select timestamp, tx_hash, auction_type, bid_total, est_profit from filled_auctions;'
echo ybx:
sqlite3 data-ybx/auctioneer.sqlite  'select timestamp, tx_hash, auction_type, bid_total, est_profit from filled_auctions;'
echo fxdao:
sqlite3 data-fxdao/auctioneer.sqlite  'select timestamp, tx_hash, auction_type, bid_total, est_profit from filled_auctions;'
