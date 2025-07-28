#!/bin/sh

F=$1

#file1=`/bin/ls -1t data/logs/main* |head -1`
#file2=`/bin/ls -1t data-ybx/logs/main* |head -1`
#file3=`/bin/ls -1t data-fxdao/logs/main* |head -1`
file4=`/bin/ls -1t data-refl/logs/main* |head -1`
file5=`/bin/ls -1t data-v2/logs/main* |head -1`

#tail -n 1000 $F $file |
#    grep 'Processing pool event' |
#    jq .message |
#    perl -ne 's/Processing pool event: //; print eval("$_")."\n"' |
#    jq .

#tail -q -n 10 $F $file1 $file2 $file3 | jq .

f1() {
    [ -z "$1" ] && return
    echo $1
    tail -n 2 $1 | jq . | grep '"timestamp"'
}
f2() {
    [ -z "$1" ] && return
    echo $1
    tail -n 3 $1 | jq .
}

if [ "$1" = "1" ] ; then
#    f1 $file1
#    f1 $file2
#    f1 $file3
    f1 $file4
    f1 $file5
    exit
fi
if [ "$1" = "2" ] ; then
#    f2 $file1
#    f2 $file2
#    f2 $file3
    f2 $file4
    f2 $file5
    exit
fi

echo '= trades ='
#sqlite3 data/auctioneer.sqlite  'select timestamp, tx_hash, auction_type, bid_total, est_profit from filled_auctions;' | awk '{print "FIX: " $0}'
#sqlite3 data-ybx/auctioneer.sqlite  'select timestamp, pool_id, auction_type, bid_total, est_profit from filled_auctions;' | awk '{print "YBX: " $0}'
#sqlite3 data-fxdao/auctioneer.sqlite  'select timestamp, pool_id, auction_type, bid_total, est_profit from filled_auctions;' | awk '{print "FXW: " $0}'
sqlite3 data-refl/auctioneer.sqlite  "select datetime(timestamp, 'unixepoch', 'localtime') , pool_id, auction_type, bid_total, est_profit from filled_auctions;" | awk '{print "RFL: " $0}'
sqlite3 data-v2/auctioneer.sqlite  "select datetime(timestamp, 'unixepoch', 'localtime') , pool_id, auction_type, bid_total, est_profit from filled_auctions;" | awk '{print "V2 : " $0}'
