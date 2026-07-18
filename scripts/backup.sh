#!/usr/bin/env bash
# Nightly backup: pg_dump ColdTrace, snapshot airmon SQLite dbs, mirror offsite.
#
# Local snapshots land in $BACKUPS (14-day rolling prune). If REMOTE_BACKUP_TARGET
# is set, files are copied (not synced) to that rclone remote after each run, so
# the offsite copy accumulates independently of the local prune. The bucket
# MUST have its own lifecycle expiry rule (30-90 days) or it grows unbounded --
# nothing in this script deletes remote objects. See docs/recovery.md section 6b.
#
# Expected /etc/homelab/backup.env when driven by homelab-backup.service:
#     REMOTE_BACKUP_TARGET=r2:homelab-pi-backups/nightly
#     RCLONE_CONFIG=/root/.config/rclone/rclone.conf
#     # optional overrides:
#     # BACKUPS=/srv/data/backups
#     # KEEP_DAYS=14
#
# rclone version pin: needs >= 1.74. Debian trixie ships 1.60.1, which throws
# 501 NotImplemented against R2 (post-upload HEAD with ?versionId= that R2
# does not support). bootstrap-pi.sh installs the official .deb; do not
# `apt install rclone`.
#
# Secrets tarball: /etc/homelab/backup-passphrase (root:root 0600) must exist,
# and its content must ALSO live in the operator's password manager. The tarball
# is encrypted before it touches $BACKUPS, so plaintext secrets never enter the
# offsite-mirrored dir. The passphrase is not inside the tarball on purpose
# (bootstrap paradox: you need it to decrypt everything else). See
# docs/recovery.md §6b.

set -euo pipefail

BACKUPS=${BACKUPS:-/srv/data/backups}
KEEP_DAYS=${KEEP_DAYS:-14}
SECRETS_PASSPHRASE_FILE=${SECRETS_PASSPHRASE_FILE:-/etc/homelab/backup-passphrase}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)

mkdir -p "$BACKUPS"

echo "== pg_dump coldtrace =="
sudo -u postgres pg_dump --clean --if-exists coldtrace \
    | gzip > "$BACKUPS/coldtrace-$STAMP.sql.gz"

echo "== sqlite airmon =="
# online .backup gives a consistent snapshot without stopping the app.
# buffer.db is deliberately NOT backed up: it is the agent's offline queue,
# every row is marked sent=1 once the server 2xx's, and those same rows are
# already durable in server.db. Backing it up was ~40% of nightly R2 volume
# for zero unique bytes. On rebuild, the agent recreates an empty buffer.db
# on first start.
for db in server.db; do
    src=/srv/data/airmon/$db
    [[ -f $src ]] || continue
    sqlite3 "$src" ".backup '$BACKUPS/${db%.db}-$STAMP.db'"
done

if [[ -r $SECRETS_PASSPHRASE_FILE ]]; then
    echo "== encrypt config/secrets tarball =="
    out=$BACKUPS/secrets-$STAMP.tar.gz.gpg
    tmp=$out.partial
    # Pipe tar -> gpg so plaintext lives only in a pipe buffer, never on disk.
    # --ignore-failed-read: a target missing on this host is not a failure
    # (e.g. a Pi that doesn't run coldtrace still backs up what it does have).
    (
        umask 077
        tar --create --gzip --ignore-failed-read --file - \
            /etc/homelab/cloudflare.env \
            /etc/homelab/backup.env \
            /root/.config/rclone/rclone.conf \
            /home/umut/coldtrace/apps/backend/.env \
            /home/umut/.coldtrace-setup/db_password \
            /var/lib/caddy \
            2>/dev/null \
          | gpg --batch --yes --quiet --symmetric \
                --cipher-algo AES256 \
                --passphrase-file "$SECRETS_PASSPHRASE_FILE" \
                --output "$tmp"
    )
    mv "$tmp" "$out"
else
    echo "== SKIPPING secrets tarball: $SECRETS_PASSPHRASE_FILE not readable =="
    echo "   Create it (mode 0600, root:root) with a strong passphrase and save"
    echo "   a copy to your password manager. See docs/recovery.md section 6b."
fi

echo "== prune older than $KEEP_DAYS days =="
find "$BACKUPS" -maxdepth 1 -type f \
    \( -name '*.sql.gz' -o -name '*.db' -o -name '*.tar.gz.gpg' \) \
    -mtime "+$KEEP_DAYS" -print -delete

if [[ -n ${REMOTE_BACKUP_TARGET:-} ]]; then
    echo "== rclone copy to $REMOTE_BACKUP_TARGET =="
    # `copy` not `sync`: local prune must not cascade to the remote copy.
    # Exclude .partial so an interrupted encryption never mirrors offsite.
    rclone copy "$BACKUPS/" "$REMOTE_BACKUP_TARGET" \
        --transfers=4 --checkers=8 \
        --exclude='.*' \
        --exclude='*.partial' \
        --stats=0
fi

echo "done"
