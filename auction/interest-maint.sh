#!/bin/bash

DSTR=`date +%Y%m%d%H%M%S`

while true ; do
    echo ================
    date
    ./new-interest-v3.sh
    sleep 1h
done 2>&1 | tee new-interest-v3.sh.$DSTR.log
