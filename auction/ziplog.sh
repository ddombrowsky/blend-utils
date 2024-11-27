#!/bin/sh

set -e

sudo sh -c 'date > data/logs/timestamp'

dstr=`date +%s`
tar cvfJ logs-$dstr.tar.xz data/logs 

sudo rm ./data/logs/*
