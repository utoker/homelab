#!/usr/bin/env bash
# Dead-man's-switch ping to healthchecks.io for airmon. Called every 15 min by
# homelab-healthcheck.timer. Pings only when the whole chain is healthy:
#   1. a reading landed in the last $FRESH_S seconds (proves the sensors, the
#      agent, airmon-server and the /srv/data SSD are all working);
#   2. https://airmon.utoker.com answers through Cloudflare (proves DNS, the
#      Cloudflare proxy, the router port-forward and Caddy).
#
# On failure it posts the reason to the check's /log endpoint, which records it
# without changing state. healthchecks.io alerts once pings stop for longer
# than period + grace. A dead or offline Pi sends no ping at all, which is the
# case this exists for: the 2026-10-20 outage went unnoticed for ~4 days.
#
# Requires env var (from /etc/homelab/healthchecks.env):
#   HC_PING_URL_AIRMON      https://hc-ping.com/<uuid>
#
# Requires: curl, jq.

set -euo pipefail

: "${HC_PING_URL_AIRMON:?HC_PING_URL_AIRMON not set}"

API=http://127.0.0.1:8000/api
PUBLIC_URL=https://airmon.utoker.com/api/health
FRESH_S=${FRESH_S:-120}

log() { printf '%s healthcheck: %s\n' "$(date -Iseconds)" "$*"; }

problems=()

since=$(date -u -d "-${FRESH_S} sec" +%Y-%m-%dT%H:%M:%SZ)
if count=$(curl -fsS -m 10 "$API/readings?since=$since&resolution=5s" | jq -er '.count'); then
    (( count > 0 )) || problems+=("no readings in the last ${FRESH_S}s")
else
    problems+=("local API $API/readings not answering")
fi

# Plain DNS on purpose: the Pi resolves this name to Cloudflare's proxy, so the
# request leaves the house and comes back in through the router. If a LAN
# split-horizon rewrite (docs/dns-lan.md) is ever applied to the Pi itself,
# this stops exercising the public path.
code=$(curl -sS -m 15 -o /dev/null -w '%{http_code}' "$PUBLIC_URL" || true)
[[ $code == 200 ]] || problems+=("public $PUBLIC_URL returned ${code:-no response}")

if (( ${#problems[@]} == 0 )); then
    curl -fsS -m 10 --retry 3 -o /dev/null "$HC_PING_URL_AIRMON"
    log "ok ($count readings in last ${FRESH_S}s); pinged"
else
    msg=$(printf '%s; ' "${problems[@]}")
    msg=${msg%; }
    log "UNHEALTHY: $msg"
    curl -fsS -m 10 --retry 3 -o /dev/null --data-raw "$msg" "$HC_PING_URL_AIRMON/log" || true
    exit 1
fi
