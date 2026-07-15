#!/usr/bin/env bash
# Deploy airmon on the Pi from the git checkout at ~/airmon.
# Builds the SPA and restarts the systemd units. Run as `umut`.
#
# Assumes:
#   ~/airmon           git checkout of utoker/airmon (pi/ subdir)
#   ~/airmon-server    git checkout of utoker/airmon (server/ subdir) or a copy
#   ~/airmon-web       built SPA (populated by this script from ~/airmon/web/dist)
#
# Bootstrap of these dirs is in docs/recovery.md.

set -euo pipefail

log() { printf '\n== %s ==\n' "$*"; }

REPO=${AIRMON_REPO:-$HOME/airmon}

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
