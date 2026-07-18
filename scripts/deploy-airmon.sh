#!/usr/bin/env bash
# Deploy airmon on the Pi from the git checkout at ~/airmon-repo.
# Builds the SPA and restarts the systemd units. Run as `umut`.
#
# Layout:
#   ~/airmon-repo      git checkout of utoker/airmon (source of truth)
#   ~/airmon           runtime copy of pi/ (rsync target; venv lives here)
#   ~/airmon-server    runtime copy of server/ (rsync target; venv lives here)
#   ~/airmon-web       built SPA (populated by this script from web/dist)
#
# The checkout MUST be at a different path from ~/airmon: rsync'ing
# pi/ into ~/airmon would erase the checkout under itself.
#
# Bootstrap of these dirs is in docs/recovery.md.

set -euo pipefail

log() { printf '\n== %s ==\n' "$*"; }

REPO=${AIRMON_REPO:-$HOME/airmon-repo}

if [[ "$(readlink -f "$REPO")" == "$(readlink -f "$HOME/airmon")" ]]; then
    echo "ERROR: AIRMON_REPO ($REPO) is the same path as ~/airmon (rsync target)." >&2
    echo "Clone the repo to a distinct path (default ~/airmon-repo) and retry." >&2
    exit 1
fi

log "pull latest"
git -C "$REPO" pull --ff-only

log "sync pi/ code"
rsync -a --delete --exclude '.venv' --exclude '__pycache__' \
    "$REPO/pi/" "$HOME/airmon/"

log "sync server/ code"
rsync -a --delete --exclude '.venv' --exclude '__pycache__' --exclude '*.db' \
    "$REPO/server/" "$HOME/airmon-server/"

log "build web/ and publish to ~/airmon-web"
cd "$REPO/web"
npm ci --no-audit --no-fund
npm run build
rsync -a --delete "$REPO/web/dist/" "$HOME/airmon-web/"

log "restart services"
sudo systemctl restart airmon-server.service airmon-agent.service
sleep 3
systemctl --no-pager -n 5 status airmon-server.service airmon-agent.service | tail -n 20

log "done"
