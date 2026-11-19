#!/bin/bash

DSTR=`date +%Y%m%d%H%M%S`
LOGFILE=new-interest-v3.sh.$DSTR.log

while true ; do
    echo ================
    date
    ./new-interest-v3.sh
    sleep 1h
done | ts > $LOGFILE 2>&1 &

echo logging to $LOGFILE
