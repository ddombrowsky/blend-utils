#!/bin/bash

# Poll the aggregator's lastprice for every asset once a minute and log
# the results to a local sqlite db, to confirm the Reflector feed is
# steady (no gaps, no stale prices, no max_dev rejections).
#
# The asset list is read from deploy-aggregator.sh, plus USDC (the base).
# Queries are simulations only; nothing is sent.
#
# usage:
#   ./watch-prices.sh [id]          # poll forever (Ctrl-C to stop)
#   ./watch-prices.sh report [id]   # summarize what's been logged
#
# Long runs:  nohup ./watch-prices.sh > watch-prices.log 2>&1 &
#
# env: DB (default prices.db), INTERVAL (default 60 seconds)

cd "$(dirname "$0")"

ID_DEFAULT=CDN7JD6SP32RZHB3DHK4S4AWCCQF6GYIUO455UCR4RGRZILZDRD24N36
DB=${DB:-prices.db}
INTERVAL=${INTERVAL:-60}
NETWORK=mainnet
SOURCE=xbull
USDC=CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75

# pull ASSETS="..." out of deploy-aggregator.sh without running it
eval "$(sed -n '/^ASSETS="/,/"$/p' deploy-aggregator.sh)"
ASSETS="USDC $USDC 0
$ASSETS"

sqlite3 $DB <<'EOF'
CREATE TABLE IF NOT EXISTS prices (
    poll_ts   INTEGER NOT NULL,  -- unix time we queried
    asset     TEXT    NOT NULL,
    price     INTEGER,           -- 7 decimals; NULL if no price
    oracle_ts INTEGER,           -- timestamp reported with the price
    error     TEXT               -- raw output when there was no price
);
CREATE INDEX IF NOT EXISTS prices_asset_ts ON prices (asset, poll_ts);
EOF

report() {
    sqlite3 -header -column $DB <<'EOF'
SELECT datetime(min(poll_ts), 'unixepoch', 'localtime') AS first_poll,
       datetime(max(poll_ts), 'unixepoch', 'localtime') AS last_poll,
       count(DISTINCT poll_ts)             AS polls
FROM prices;

-- age = how old the oracle's price was when we polled (max_age is 900)
-- max_step = biggest % change between consecutive distinct oracle rounds
WITH r AS (
    SELECT asset, price, oracle_ts, poll_ts,
           lag(price) OVER (PARTITION BY asset ORDER BY poll_ts) AS prev
    FROM prices WHERE price IS NOT NULL
)
SELECT p.asset,
       count(*)                                   AS polls,
       sum(p.price IS NULL)                       AS missing,
       printf('%.7f', min(p.price) / 1e7)         AS min,
       printf('%.7f', max(p.price) / 1e7)         AS max,
       printf('%.7f', (SELECT price FROM prices WHERE asset = p.asset
                       AND price IS NOT NULL ORDER BY poll_ts DESC
                       LIMIT 1) / 1e7)            AS last,
       count(DISTINCT p.oracle_ts)                AS rounds,
       max(p.poll_ts - p.oracle_ts)               AS max_age_s,
       (SELECT printf('%.2f%%', max(abs(price - prev) * 100.0 / prev))
        FROM r WHERE r.asset = p.asset AND prev IS NOT NULL
        AND prev != price)                        AS max_step
FROM prices p
GROUP BY p.asset
ORDER BY min(rowid);
EOF
    echo
    echo "recent errors:"
    sqlite3 $DB "SELECT datetime(poll_ts,'unixepoch', 'localtime'), asset, error
                 FROM prices WHERE price IS NULL
                 ORDER BY poll_ts DESC LIMIT 10"
}

if [ "$1" = report ]; then
    report
    exit 0
fi

ID=${1:-$ID_DEFAULT}
echo "polling $ID every ${INTERVAL}s into $DB (Ctrl-C to stop)"

while true; do
    now=$(date +%s)
    sql="BEGIN;"
    line="$(date '+%F %T')"
    while read name addr maxdev; do
        [ -n "$name" ] || continue
        out=$(stellar contract invoke --id $ID --source-account $SOURCE \
            --network $NETWORK --send no -- \
            lastprice --asset "{\"Stellar\":\"$addr\"}" 2>&1 | tail -1)
        if [[ $out =~ \"price\":\"([0-9]+)\",\"timestamp\":([0-9]+) ]]; then
            price=${BASH_REMATCH[1]}
            ots=${BASH_REMATCH[2]}
            sql+="INSERT INTO prices VALUES ($now,'$name',$price,$ots,NULL);"
            line+=" $name=$(printf '%.4g' "$(bc -l <<< "$price/10^7")")"
        else
            err=${out//\'/\'\'}
            sql+="INSERT INTO prices VALUES ($now,'$name',NULL,NULL,'$err');"
            line+=" $name=MISSING"
        fi
    done <<< "$ASSETS"
    sqlite3 $DB "$sql COMMIT;"
    echo "$line"
    # sleep to the next interval boundary
    sleep $(( INTERVAL - ($(date +%s) - now) % INTERVAL ))
done
