#!/bin/sh
# Create BLNT v3 interest auctions on every v3 pool.  See interest-v3.py.
# Pass --dry-run to simulate new_auction instead of sending it.

cd "$(dirname "$0")"

LOG=auction.log
: > $LOG

for pool in \
    fixed=CACSQWCMKG45TUHCQ3LXHOB7YEEJH4W376ZHQPXH2IZ3TE4NJHFZMCY7 \
    yieldblent=CAUTPSQDAJEUV5XEU3EXFVYRGDJLEJGVTFJCFZCSPTDCREAMZ573VF4D
do
    python3 interest-v3.py "$@" "${pool%%=*}" "${pool#*=}" 2>&1 | tee -a $LOG
done
