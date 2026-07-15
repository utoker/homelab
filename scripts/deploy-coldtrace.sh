#!/usr/bin/env bash
# Deploy ColdTrace backend on the Pi from the git checkout at ~/coldtrace.
# Frontend stays on Vercel (auto-deployed from GitHub) — this script only
# handles the Pi-side backend. Run as `umut`.

set -euo pipefail

log() { printf '\n== %s ==\n' "$*"; }

REPO=${COLDTRACE_REPO:-$HOME/coldtrace}

log "pull latest"
git -C "$REPO" pull --ff-only

log "install + build backend workspace"
cd "$REPO"
pnpm install --no-frozen-lockfile
pnpm --filter backend build

log "restart backend service"
sudo systemctl restart coldtrace-backend.service
sleep 3
systemctl --no-pager -n 10 status coldtrace-backend.service | tail -n 20

log "done"
