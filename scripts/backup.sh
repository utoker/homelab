#!/usr/bin/env bash
# Nightly backup: pg_dump ColdTrace, snapshot airmon SQLite dbs.
# Writes to /mnt/ssd/backups with 14-day retention. Optionally rsync
# to a remote host if REMOTE_BACKUP_TARGET is set (rsync over SSH).

set -euo pipefail

BACKUPS=${BACKUPS:-/mnt/ssd/backups}
KEEP_DAYS=${KEEP_DAYS:-14}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)

mkdir -p "$BACKUPS"

echo "== pg_dump coldtrace =="
sudo -u postgres pg_dump --clean --if-exists coldtrace \
    | gzip > "$BACKUPS/coldtrace-$STAMP.sql.gz"

echo "== sqlite airmon =="
# online .backup gives a consistent snapshot without stopping the app
for db in server.db buffer.db; do
    src=/mnt/ssd/airmon-data/$db
    [[ -f $src ]] || continue
    sqlite3 "$src" ".backup '$BACKUPS/${db%.db}-$STAMP.db'"
done

echo "== prune older than $KEEP_DAYS days =="
find "$BACKUPS" -maxdepth 1 -type f \( -name '*.sql.gz' -o -name '*.db' \) \
    -mtime "+$KEEP_DAYS" -print -delete

if [[ -n ${REMOTE_BACKUP_TARGET:-} ]]; then
    echo "== rsync to $REMOTE_BACKUP_TARGET =="
    rsync -a --delete "$BACKUPS/" "$REMOTE_BACKUP_TARGET/"
fi

echo "done"
