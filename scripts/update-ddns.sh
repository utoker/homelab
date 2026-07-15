#!/usr/bin/env bash
# Update Porkbun A records for airmon.utoker.com and api.coldtrace.app
# to the current public IP. Called every 5 min by the homelab-ddns.timer.
#
# Requires env vars (from /etc/homelab/porkbun.env):
#   PORKBUN_API_KEY     (pk1_...)
#   PORKBUN_SECRET      (sk1_...)
#
# Requires: curl, jq. Idempotent; only PATCHes if IP has changed.

set -euo pipefail

: "${PORKBUN_API_KEY:?PORKBUN_API_KEY not set}"
: "${PORKBUN_SECRET:?PORKBUN_SECRET not set}"

PORKBUN_API="https://api.porkbun.com/api/json/v3"
TTL="${DDNS_TTL:-300}"

# (domain, type, subdomain) tuples to keep synced.
RECORDS=(
    "utoker.com|A|airmon"
    "coldtrace.app|A|api"
)

log() { printf '%s ddns: %s\n' "$(date -Iseconds)" "$*"; }

get_public_ip() {
    curl -fsS --max-time 10 https://api.ipify.org
}

porkbun_get() {
    local domain=$1 type=$2 sub=$3
    curl -fsS --max-time 15 \
        -H 'Content-Type: application/json' \
        -d "{\"apikey\":\"$PORKBUN_API_KEY\",\"secretapikey\":\"$PORKBUN_SECRET\"}" \
        "$PORKBUN_API/dns/retrieveByNameType/$domain/$type/$sub"
}

porkbun_edit() {
    local domain=$1 type=$2 sub=$3 ip=$4
    curl -fsS --max-time 15 \
        -H 'Content-Type: application/json' \
        -d "{\"apikey\":\"$PORKBUN_API_KEY\",\"secretapikey\":\"$PORKBUN_SECRET\",\"content\":\"$ip\",\"ttl\":\"$TTL\"}" \
        "$PORKBUN_API/dns/editByNameType/$domain/$type/$sub"
}

main() {
    local current_ip
    current_ip=$(get_public_ip) || { log "ipify unreachable, skipping"; exit 0; }
    log "public ip: $current_ip"

    local drift=0
    for rec in "${RECORDS[@]}"; do
        IFS='|' read -r domain type sub <<<"$rec"
        local fqdn="${sub:+${sub}.}${domain}"

        local existing
        existing=$(porkbun_get "$domain" "$type" "$sub" | jq -r '.records[0].content // empty')
        if [[ -z $existing ]]; then
            log "$fqdn: no record found; skipping (create it manually first)"
            continue
        fi

        if [[ $existing == "$current_ip" ]]; then
            log "$fqdn: already $current_ip"
        else
            log "$fqdn: $existing -> $current_ip"
            local resp
            resp=$(porkbun_edit "$domain" "$type" "$sub" "$current_ip")
            if [[ $(jq -r '.status' <<<"$resp") == "SUCCESS" ]]; then
                log "$fqdn: updated"
                drift=1
            else
                log "$fqdn: FAILED — $resp"
                exit 1
            fi
        fi
    done

    exit 0
}

main "$@"
