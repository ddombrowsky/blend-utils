#!/bin/sh

F=$1

file1=`/bin/ls -1t data/logs/main* |head -1`
file2=`/bin/ls -1t data-ybx/logs/main* |head -1`
file3=`/bin/ls -1t data-fxdao/logs/main* |head -1`
file4=`/bin/ls -1t data-refl/logs/main* |head -1`
file5=`/bin/ls -1t data-v2/logs/main* |head -1`

#tail -n 1000 $F $file |
#    grep 'Processing pool event' |
#    jq .message |
#    perl -ne 's/Processing pool event: //; print eval("$_")."\n"' |
#    jq .

#tail -q -n 10 $F $file1 $file2 $file3 | jq .
if [ "$1" = "1" ] ; then
    echo $file1
    tail -n 2 $file1 | jq . | grep '"timestamp"'
    echo $file2
    tail -n 2 $file2 | jq . | grep '"timestamp"'
    echo $file3
    tail -n 2 $file3 | jq . | grep '"timestamp"'
    echo $file4
    tail -n 2 $file4 | jq . | grep '"timestamp"'
    echo $file5
    tail -n 2 $file5 | jq . | grep '"timestamp"'
    exit
fi
if [ "$1" = "2" ] ; then
    echo $file1
    tail -n 3 $file1 | jq .
    echo $file2
    tail -n 3 $file2 | jq .
    echo $file3
    tail -n 3 $file3 | jq .
    echo $file4
    tail -n 3 $file4 | jq .
    echo $file5
    tail -n 3 $file5 | jq .
    exit
fi

echo '= trades ='
sqlite3 data/auctioneer.sqlite  'select timestamp, tx_hash, auction_type, bid_total, est_profit from filled_auctions;' | awk '{print "FIX: " $0}'
sqlite3 data-ybx/auctioneer.sqlite  'select timestamp, tx_hash, auction_type, bid_total, est_profit from filled_auctions;' | awk '{print "YBX: " $0}'
sqlite3 data-fxdao/auctioneer.sqlite  'select timestamp, tx_hash, auction_type, bid_total, est_profit from filled_auctions;' | awk '{print "FXW: " $0}'
sqlite3 data-refl/auctioneer.sqlite  'select timestamp, tx_hash, auction_type, bid_total, est_profit from filled_auctions;' | awk '{print "RFL: " $0}'
sqlite3 data-v2/auctioneer.sqlite  'select timestamp, tx_hash, auction_type, bid_total, est_profit from filled_auctions;' | awk '{print "V2 : " $0}'
