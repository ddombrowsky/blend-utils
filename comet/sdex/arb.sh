#!/bin/sh
#

# run example:
#    timeout -s SIGINT 2h ./arb.sh --execute

set -x

#export SECRET_KEY=$(stellar keys show claudio)
export SECRET_KEY=$(stellar keys show xbull)

EX=
[ "$1" = "--execute" ] && EX=--execute

node arb.js --usdc 13 --min-profit 0.5 --poll 120 $EX
