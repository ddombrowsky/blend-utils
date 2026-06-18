#!/bin/sh
#

set -x

export SECRET_KEY=$(stellar keys show claudio)

EX=
[ "$1" = "--execute" ] && EX=--execute

node arb.js --usdc 13 --min-profit 0.5 --poll 30 $EX
