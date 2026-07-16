#!/usr/bin/env bash
# Update Cloudflare A records for airmon.utoker.com and api.coldtrace.app
# to the current public IP. Called every 5 min by the homelab-ddns.timer.
#
# Requires env vars (from /etc/homelab/cloudflare.env):
#   CF_API_TOKEN            scoped Zone.DNS:Edit token
#   CF_ZONE_ID_UTOKER       utoker.com zone id
#   CF_RECORD_ID_AIRMON     airmon.utoker.com A-record id
#   CF_ZONE_ID_COLDTRACE    coldtrace.app zone id
#   CF_RECORD_ID_API        api.coldtrace.app A-record id
#
# Requires: curl, jq. Idempotent; only PATCHes if IP has changed.

set -euo pipefail

: "${CF_API_TOKEN:?CF_API_TOKEN not set}"
: "${CF_ZONE_ID_UTOKER:?CF_ZONE_ID_UTOKER not set}"
: "${CF_RECORD_ID_AIRMON:?CF_RECORD_ID_AIRMON not set}"
: "${CF_ZONE_ID_COLDTRACE:?CF_ZONE_ID_COLDTRACE not set}"
: "${CF_RECORD_ID_API:?CF_RECORD_ID_API not set}"

CF_API="https://api.cloudflare.com/client/v4"

# (fqdn, zone_id, record_id) tuples to keep synced.
RECORDS=(
    "airmon.utoker.com|$CF_ZONE_ID_UTOKER|$CF_RECORD_ID_AIRMON"
    "api.coldtrace.app|$CF_ZONE_ID_COLDTRACE|$CF_RECORD_ID_API"
)

log() { printf '%s ddns: %s\n' "$(date -Iseconds)" "$*"; }

get_public_ip() {
    curl -fsS --max-time 10 https://api.ipify.org
}

cf_get() {
    local zone=$1 rec=$2
    curl -fsS --max-time 15 \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        "$CF_API/zones/$zone/dns_records/$rec"
}

cf_patch() {
    local zone=$1 rec=$2 ip=$3
    curl -fsS --max-time 15 -X PATCH \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H 'Content-Type: application/json' \
        -d "{\"content\":\"$ip\"}" \
        "$CF_API/zones/$zone/dns_records/$rec"
}

main() {
    local current_ip
    current_ip=$(get_public_ip) || { log "ipify unreachable, skipping"; exit 0; }
    log "public ip: $current_ip"

    for rec in "${RECORDS[@]}"; do
        IFS='|' read -r fqdn zone record_id <<<"$rec"

        local resp existing
        resp=$(cf_get "$zone" "$record_id")
        existing=$(jq -r '.result.content // empty' <<<"$resp")
        if [[ -z $existing ]]; then
            log "$fqdn: no record found; check CF_RECORD_ID / token scope"
            exit 1
        fi

        if [[ $existing == "$current_ip" ]]; then
            log "$fqdn: already $current_ip"
        else
            log "$fqdn: $existing -> $current_ip"
            resp=$(cf_patch "$zone" "$record_id" "$current_ip")
            if [[ $(jq -r '.success' <<<"$resp") == "true" ]]; then
                log "$fqdn: updated"
            else
                log "$fqdn: FAILED — $resp"
                exit 1
            fi
        fi
    done

    exit 0
}

main "$@"
