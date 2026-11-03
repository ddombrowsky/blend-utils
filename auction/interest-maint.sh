#!/bin/bash

while true ; do
    echo ================
    date
    ./new-interest-v3.sh
    sleep 1h
done 2>&1 | tee log
