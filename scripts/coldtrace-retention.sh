#!/usr/bin/env bash
# Daily ColdTrace retention: drop readings older than $KEEP_DAYS.
#
# Readings are simulator-generated and regenerable, so old ones carry no value.
# Alerts are NOT touched: they are the excursion history, they are tiny, and
# alerts.deviceId references devices (not readings), so pruning readings cannot
# cascade into them.
#
# Expected /etc/homelab/coldtrace-retention.env (optional):
#     KEEP_DAYS=180

set -euo pipefail

KEEP_DAYS=${KEEP_DAYS:-180}
DB=${DB:-coldtrace}

psql_q() { sudo -u postgres psql -d "$DB" -t -A -c "$1"; }

before=$(psql_q "SELECT COUNT(*) FROM readings;")
echo "== coldtrace retention: keeping ${KEEP_DAYS} days =="
echo "readings before: $before"

deleted=$(psql_q "WITH d AS (
    DELETE FROM readings
    WHERE timestamp < NOW() - INTERVAL '${KEEP_DAYS} days'
    RETURNING 1
) SELECT COUNT(*) FROM d;")
echo "deleted: $deleted"

# Plain VACUUM (never FULL): marks space reusable without an exclusive lock, so
# the table reaches a steady size. VACUUM FULL would rewrite it and block writes.
if [[ $deleted -gt 0 ]]; then
    echo "== vacuum analyze =="
    sudo -u postgres psql -d "$DB" -c "VACUUM (ANALYZE) readings;" >/dev/null
fi

after=$(psql_q "SELECT COUNT(*) FROM readings;")
alerts=$(psql_q "SELECT COUNT(*) FROM alerts;")
echo "readings after: $after"
echo "alerts (untouched): $alerts"
echo "done"
