#!/bin/bash
# Step 5 of cover-reserve.txt -- take the Blent Covered Pool out of setup
# (6) straight into Admin Frozen (4).  cover-hours.sh tick (cron, as the
# blnt-keeper user) then opens it during business hours when the cover
# check passes.
#
#   ./go-live-covered.sh        (as yourself; asks for sudo at the end)
#
# One-way: leaving setup starts the 7-day timelock on every reserve
# change.  The preflight is read-only and runs as you; the one send is the
# keeper's installed copy, as the keeper:
#   sudo -u blnt-keeper -H /opt/blnt-keeper/cover-hours.sh freeze
# which calls the pool-status-manager's set_status, signed by the operator.

set -eo pipefail
cd "$(dirname "$0")"

POOL=CCH3BNZWTTBB2AKX6NT5OGKQSWP4UNBIKRTRMRDKKJLPMFKULHQZC3XD
MANAGER=CCP7DMV4WCVPH2C6ZETXCBFXDPQRLN27CQEAHVILEFWUM7QCG6DMIVDQ
OPERATOR=GAF6YOV7NXCTGR6U2CKZURLD5I7EB4AL5HLVYI3E3VR3C5A2FAY7LT43
FUND=GDA5JJFUAGFBNT4BMEGASY7EWBJFOWL2VBXMYY6QKCEOZMXHX6BBXYOB
BACKSTOP=CAHCUKBPTW5DR5RNXOHCTJD5U76A6EEZXYZAQFRQEEQRXQ3CRUZ6Z3MO
KUSER=blnt-keeper
KHOME=/var/lib/blnt-keeper
OPT=/opt/blnt-keeper
HORIZON=https://horizon.stellar.org

view() {
    stellar contract invoke --source-account $OPERATOR --network mainnet \
        --send no --id "$@" 2>/dev/null | tail -1 || true
}
fail() { echo "*** $*"; FAILED=1; }
FAILED=0

echo "== 0. preflight"
CONFIG=$(view $POOL -- get_config)
echo "config   $CONFIG"
case "$CONFIG" in *'"status":6'*) ;; *) echo "*** pool is not in setup (6); nothing to do"; exit 1;; esac

N=$(view $POOL -- get_reserve_list | jq length)
echo "reserves $N"
[ "$N" = 3 ] || fail "expected 3 reserves"

BS=$(view $BACKSTOP -- pool_data --pool $POOL)
echo "backstop $BS"
[ "$(echo "$BS" | jq -r '(.active_value|tonumber) > 0')" = true ] || fail "no backstop deposit"

A=$(view $POOL -- get_admin | tr -d '"')
echo "pool admin $A"
[ "$A" = "$MANAGER" ] || fail "pool admin is not the manager $MANAGER"
O=$(view $MANAGER -- get_owner | tr -d '"'); P=$(view $MANAGER -- get_operator | tr -d '"')
echo "manager owner $O, operator $P"
[ "$O" = "$FUND" ] || fail "manager owner is not the fund"
[ "$P" = "$OPERATOR" ] || fail "manager operator is not $OPERATOR"

OPXLM=$(curl -sf $HORIZON/accounts/$OPERATOR | jq -r '.balances[] | select(.asset_type=="native") | .balance') || true
echo "operator XLM ${OPXLM:-?}"
[ -n "$OPXLM" ] && [ "$(jq -n "$OPXLM >= 2")" = true ] || fail "operator needs >= 2 XLM for fees"

ACCT=$(curl -sf $HORIZON/accounts/$FUND) || { fail "fund account $FUND not found"; ACCT='{}'; }
echo "fund signers: $(echo "$ACCT" | jq -c '[.signers[]? | {key: .key[0:8], weight}]')"
echo "fund thresholds: $(echo "$ACCT" | jq -c '.thresholds')"
[ "$(echo "$ACCT" | jq '[.signers[]? | select(.weight > 0)] | length')" = 3 ] || fail "fund needs 3 signers"
[ "$(echo "$ACCT" | jq '.thresholds.med_threshold')" = 2 ] || fail "fund med threshold must be 2"
[ "$(echo "$ACCT" | jq '.thresholds.high_threshold')" = 2 ] || fail "fund high threshold must be 2"

echo
./cover-hours.sh check || fail "cover check fails"

[ -f cover-holidays.txt ] || fail "missing cover-holidays.txt"
grep -q "^$(date +%Y)-" cover-holidays.txt || fail "cover-holidays.txt has no dates for this year"

echo
echo "keeper install ($OPT) vs this directory:"
for f in cover-hours.sh cover-holidays.txt; do
    if cmp -s "$f" "$OPT/$f"; then echo "  $f same"
    else fail "$OPT/$f differs from ./$f; re-run: sudo ./setup-keeper.sh"; fi
done
id $KUSER >/dev/null 2>&1 || fail "no $KUSER user; run sudo ./setup-keeper.sh"

[ "$FAILED" = 0 ] || { echo; echo "preflight failed; nothing sent"; exit 1; }

echo
echo "Before going on, confirm by hand:"
echo "  * site live with the real pool, manager and fund addresses"
echo "  * cover terms published"
read -p "Leave setup -> Admin Frozen (4)?  This starts the 7-day reserve timelock. [y/N] " ok
[ "$ok" = y ] || { echo "stopped; nothing sent"; exit 0; }

echo "== 1. freeze, as $KUSER (sends; sudo may ask for your password)"
sudo -u $KUSER -H env STATE_DIR=$KHOME $OPT/cover-hours.sh freeze

echo "== 2. verify"
echo "config $(view $POOL -- get_config)"
echo
echo "Now: sudo ./setup-keeper.sh --cron [--mailto ADDR]"
echo "The pool opens on the next tick in business hours if the cover check passes."
