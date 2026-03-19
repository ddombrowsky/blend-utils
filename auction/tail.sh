#!/bin/sh

F=$1

file5=`/bin/ls -1t data-v2/logs/bidder* |head -1`

f1() {
    [ -z "$1" ] && return
    tail -n 2 $1 | jq -r .timestamp
}
f2() {
    [ -z "$1" ] && return
    echo $1
    tail -n 3 $1 | jq .
}

if [ "$1" = "1" ] ; then
    grep GAVG $file5 | tail -10
    f1 $file5
    date -u +"%Y-%m-%dT%H:%M:%S NOW"
    exit
fi
if [ "$1" = "2" ] ; then
    f2 $file5
    exit
fi

echo '= trades ='
sqlite3 data-v2/auctioneer.sqlite  "select datetime(timestamp, 'unixepoch', 'localtime') , substr(pool_id,1,7), tx_hash, auction_type, bid_total, est_profit from filled_auctions;" | awk '{print "V2 : " $0}'
