#!/usr/bin/env bash
# Nightly backup: pg_dump ColdTrace, snapshot airmon SQLite dbs, mirror offsite.
#
# Local snapshots land in $BACKUPS (14-day rolling prune). If REMOTE_BACKUP_TARGET
# is set, files are copied (not synced) to that rclone remote after each run, so
# the offsite copy accumulates independently of the local prune. Set an R2 (or
# equivalent) lifecycle rule if you want the remote to prune too.
#
# Expected /etc/homelab/backup.env when driven by homelab-backup.service:
#     REMOTE_BACKUP_TARGET=r2:coldtrace-pi-backups/nightly
#     RCLONE_CONFIG=/root/.config/rclone/rclone.conf
#     # optional overrides:
#     # BACKUPS=/srv/data/backups
#     # KEEP_DAYS=14

set -euo pipefail

BACKUPS=${BACKUPS:-/srv/data/backups}
KEEP_DAYS=${KEEP_DAYS:-14}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)

mkdir -p "$BACKUPS"

echo "== pg_dump coldtrace =="
sudo -u postgres pg_dump --clean --if-exists coldtrace \
    | gzip > "$BACKUPS/coldtrace-$STAMP.sql.gz"

echo "== sqlite airmon =="
# online .backup gives a consistent snapshot without stopping the app
for db in server.db buffer.db; do
    src=/srv/data/airmon/$db
    [[ -f $src ]] || continue
    sqlite3 "$src" ".backup '$BACKUPS/${db%.db}-$STAMP.db'"
done

echo "== prune older than $KEEP_DAYS days =="
find "$BACKUPS" -maxdepth 1 -type f \( -name '*.sql.gz' -o -name '*.db' \) \
    -mtime "+$KEEP_DAYS" -print -delete

if [[ -n ${REMOTE_BACKUP_TARGET:-} ]]; then
    echo "== rclone copy to $REMOTE_BACKUP_TARGET =="
    # `copy` not `sync`: local prune must not cascade to the remote copy.
    rclone copy "$BACKUPS/" "$REMOTE_BACKUP_TARGET" \
        --transfers=4 --checkers=8 \
        --exclude='.*' \
        --stats=0
fi

echo "done"
