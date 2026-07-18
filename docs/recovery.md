# Rebuild the Pi from scratch

If the SD card dies or someone rebuilds the Pi, this is the recovery order.

## 0. Prerequisites off-Pi

Everything below assumes you can reach the last-good backup AND that these
values are in your password manager (they are the ones NOT in git and NOT
inside the encrypted archive):

- **R2 credentials** — access key id + secret for the `homelab-pi-backups`
  bucket. Without these you cannot even pull the backup down.
- **Secrets-archive passphrase** — the content of `/etc/homelab/backup-passphrase`
  on the old Pi. Without this the archive is unopenable and everything else
  (Cloudflare token, rclone config, coldtrace `.env`, caddy certs) is lost.
- **Cloudflare account login** — you'll issue a new API token if the old one
  ever leaked; the DNS zone stays.
- **SSH pubkey** ready to push to the fresh Pi.

The archive is for **speed** of rebuild, not for the credentials that start it.
Both bullets above must come out of the password manager before rclone can pull
a single byte.

## 1. Fresh Pi OS install

Raspberry Pi OS Lite 64-bit, latest. Use Raspberry Pi Imager's advanced options to
preset:

- Hostname: `airmon`
- User: `umut`
- SSH: enabled, key-only, paste your workstation pubkey
- Wifi + locale as needed

Boot the Pi. From the workstation:

```bash
ssh airmon
```

## 2. Attach hardware

- The three sensors (see the airmon repo's CLAUDE.md wiring table).
- The USB SSD (do NOT format yet if you want to keep old data — mount and confirm
  `/srv/data/*` contents look right).

## 3. Bootstrap

```bash
git clone https://github.com/utoker/homelab ~/homelab
sudo ~/homelab/scripts/bootstrap-pi.sh
```

## 4. Data

If the SSD survived, skip to step 5.

Otherwise (fresh SSD):

```bash
# format + mount per docs/ssd.md
# restore Postgres from the most recent backup:
gunzip -c /path/to/coldtrace-<stamp>.sql.gz | sudo -u postgres psql -d coldtrace
# restore airmon SQLite (server.db only; buffer.db is not backed up because it
# is the agent's offline queue and every row is already durable in server.db --
# the agent recreates it empty on first start). Backups are gzipped:
gunzip -c /path/to/server-<stamp>.db.gz > /srv/data/airmon/server.db
sudo chown -R umut:umut /srv/data/airmon
```

## 5. Clone and set up each app

The airmon repo is public, so no credential is needed to clone it. The layout
splits git-source from runtime homes on purpose: `deploy-airmon.sh` rsyncs
`pi/`, `server/`, and `web/dist/` from `~/airmon-repo` into `~/airmon`,
`~/airmon-server`, and `~/airmon-web` respectively. The git checkout must
NOT be at `~/airmon`, because that path is a rsync target and would be erased.

```bash
# airmon (public repo, no auth needed)
git clone https://github.com/utoker/airmon ~/airmon-repo
mkdir -p ~/airmon ~/airmon-server ~/airmon-web
# create venvs at their runtime locations
python3 -m venv ~/airmon/.venv
~/airmon/.venv/bin/pip install -r ~/airmon-repo/pi/requirements.txt
python3 -m venv ~/airmon-server/.venv
~/airmon-server/.venv/bin/pip install -r ~/airmon-repo/server/requirements.txt
# first deploy populates ~/airmon, ~/airmon-server, ~/airmon-web from the checkout.
# deploy-airmon.sh defaults AIRMON_REPO=~/airmon-repo; override if you cloned elsewhere.
~/homelab/scripts/deploy-airmon.sh

# coldtrace (public repo; deploy runs in-place from the checkout)
git clone https://github.com/utoker/coldtrace ~/coldtrace
# create ~/coldtrace/apps/backend/.env from your password manager
~/homelab/scripts/deploy-coldtrace.sh
```

## 6. Secrets: hand-place the passphrase, then decrypt the rest

There are two tiers of secrets. The first tier lives ONLY in your password
manager and is what you need to bootstrap; the second tier lives inside the
encrypted archive and is what you need for the apps to run.

### 6.1 Tier one: hand-place from the password manager

```bash
# The passphrase. Everything else is downstream of this file.
sudo install -m 0600 -o root -g root /dev/stdin /etc/homelab/backup-passphrase \
    <<< 'paste-passphrase-from-password-manager'

# rclone.conf with the R2 access key + secret for the homelab-pi-backups bucket.
# Bootstrap doesn't ship this; you paste it in the same way.
sudo install -d -m 0700 -o root -g root /root/.config/rclone
sudo install -m 0600 -o root -g root /dev/stdin /root/.config/rclone/rclone.conf <<'EOF'
[r2]
type = s3
provider = Cloudflare
access_key_id = ...
secret_access_key = ...
endpoint = https://<account_id>.r2.cloudflarestorage.com
EOF

# backup.env (small, no secrets — but no reason not to keep it here for symmetry).
sudo install -m 0600 -o root -g root /dev/stdin /etc/homelab/backup.env <<'EOF'
REMOTE_BACKUP_TARGET=r2:homelab-pi-backups/nightly
RCLONE_CONFIG=/root/.config/rclone/rclone.conf
EOF

# Confirm R2 is reachable before you try to pull anything.
sudo RCLONE_CONFIG=/root/.config/rclone/rclone.conf rclone lsd r2:
```

### 6.2 Tier two: pull + decrypt the archive

```bash
# Pull the newest secrets archive locally.
sudo mkdir -p /srv/data/backups
NEWEST=$(sudo RCLONE_CONFIG=/root/.config/rclone/rclone.conf \
    rclone lsf r2:homelab-pi-backups/nightly/ --include 'secrets-*.tar.gz.gpg' \
    | sort | tail -1)
sudo RCLONE_CONFIG=/root/.config/rclone/rclone.conf \
    rclone copy "r2:homelab-pi-backups/nightly/$NEWEST" /srv/data/backups/

# Decrypt straight to /, restoring absolute paths inside the tarball.
# tar preserves ownership by numeric UID/GID from the source Pi; on a fresh
# install those may not match. Chown the caddy tree after extraction.
sudo sh -c "gpg --batch --quiet --decrypt \
    --passphrase-file /etc/homelab/backup-passphrase \
    /srv/data/backups/$NEWEST \
  | tar xzf - -C /"
sudo chown -R caddy:caddy /var/lib/caddy
```

You now have `cloudflare.env`, `coldtrace/apps/backend/.env`, the coldtrace DB
password, and the caddy ACME state (certs + private keys — no LE round-trip
needed at first boot). Enable the DDNS timer once `cloudflare.env` is in place.

### 6.3 Bootstrap paradox

The passphrase file is inside `/etc/homelab/` but its content is NOT inside the
archive it protects. That is deliberate. If the passphrase lived in the
archive, you would need to already have the plaintext passphrase to obtain the
encrypted copy of the passphrase, which is not a useful improvement over
storing it in your password manager to begin with. So we store it in the
password manager exactly once. The R2 credentials get the same treatment for
the same reason: you need them to pull the archive that contains everything
else.

Rule of thumb: anything you need to bootstrap the rebuild lives in the
password manager. Anything you need for the running system lives in the
encrypted archive.

## 6a. rclone lives outside the Debian archive

`bootstrap-pi.sh` installs `rclone` from the official static .deb at
`downloads.rclone.org`, not `apt install rclone`. Reason: Debian trixie ships
rclone 1.60.1, which throws `501 NotImplemented` on R2 because it issues a
post-upload HEAD with `?versionId=` and R2 does not implement object
versioning. 1.74+ removes the extra call.

Bootstrap also drops `/etc/apt/preferences.d/rclone` pinning the Debian package
to `-1`, so a stray `apt install --reinstall rclone` cannot silently downgrade
to the broken version. If you ever need to bump rclone by hand:

```bash
arch=$(dpkg --print-architecture)
curl -fsSLO "https://downloads.rclone.org/rclone-current-linux-${arch}.deb"
sudo dpkg -i "rclone-current-linux-${arch}.deb"
```

Do NOT add `no_head = true` to `rclone.conf` to work around the 1.60 bug — it
disables post-upload integrity verification, which is the only check we get on
the offsite copy.

## 6b. R2 lifecycle rules (bucket-side, not in this repo)

`backup.sh` uses `rclone copy` deliberately so a local prune cannot cascade to
the offsite copy. Object expiry is handled by R2 lifecycle rules configured
in the Cloudflare dashboard, not by anything in this repo.

**Rules currently in place on `homelab-pi-backups` (both under prefix `nightly/`):**

| Rule name              | Prefix               | Delete after |
| ---------------------- | -------------------- | ------------ |
| `expire-server-db`     | `nightly/server-`    | 30 days      |
| `expire-coldtrace-dumps` | `nightly/coldtrace-` | 30 days      |

**No rule may ever match `secrets-`.** The encrypted secrets archive is the
only offsite copy of the backup passphrase's downstream secrets (rclone.conf,
cloudflare.env, coldtrace `.env`, caddy ACME state). Delete those objects and
a fresh-Pi rebuild becomes impossible even with the password manager. The
per-prefix rules above are scoped narrowly so a future prefix change on
snapshot filenames cannot accidentally start pruning secrets. If you ever add
a new artifact type, add a matching narrow rule; do not broaden either
existing rule to `nightly/`.

**Sizing after tiered downsampling (shipped 2026-07-18):**

Airmon now aggregates raw 5s samples into per-minute buckets after 14 days
and per-hour buckets after 90 days, keeping hour rows forever. Hour storage
is ~2.3 MB/year, so `server.db` settles near **100 MB** rather than growing
without bound. Concretely:

- `server.db` gzipped snapshot settles at ~40 MB (worst case ~100 MB).
- `coldtrace-*.sql.gz` ~0.5 MB, capped further by coldtrace's own 180-day
  retention (see below).
- `secrets-*.tar.gz.gpg` ~10 KB.

With snapshots effectively bounded, a 30-day retention window keeps the
bucket well under the R2 10 GB free tier indefinitely. The lifecycle rules
are a **safety net** against accidental accumulation, not a load-bearing
cost control. Do not tighten them without also tightening the
`AIRMON_TIER_RAW_DAYS` / `AIRMON_TIER_MINUTE_DAYS` values that determine
snapshot size; the two are related.

Verify the bucket's steady state with `rclone size r2:homelab-pi-backups/nightly`
a month or two after any config change; the value should oscillate around a
plateau rather than climb monotonically.

## 6c. Retention on the Pi itself

Two systemd timers prune persistent data on the Pi so its databases stay a
predictable size. Both are installed by `bootstrap-pi.sh` and defined in the
[systemd/](../systemd/) directory here.

**`airmon-maintenance.timer` (daily at 03:45 local, `RandomizedDelaySec=15min`)**

Runs `pi/maintenance.py` followed by `server/app/maintenance.py`. Env vars set
by [systemd/airmon-maintenance.service](../systemd/airmon-maintenance.service):

- `AIRMON_BUFFER_RETENTION_DAYS=7`: Pi-side `buffer.db` drops rows with
  `sent=1` older than this. Rows still marked `sent=0` are never touched;
  they are the only durable copy while offline.
- `AIRMON_TIER_RAW_DAYS=14`: server-side `readings` table (raw 5s samples).
- `AIRMON_TIER_MINUTE_DAYS=90`: server-side `readings_minute` table.
- Hour rows in `readings_hour` are kept forever.

Order of operations on the server: roll up first (needs raw rows present),
verify a random sample of aggregate rows against a fresh raw query, then
prune raw rows past the raw cutoff, then prune minute rows past the minute
cutoff, then `VACUUM`. Rollup and pruning are separate transactions, so a
partial run never destroys rows that have not been aggregated yet. If any
verification sample fails, the run refuses to prune.

Restoring from a `server-*.db.gz` snapshot restores all three tables in a
single file. Depending on the snapshot's age, some readings will exist only
as minute or hour aggregates: raw rows beyond 14 days pre-snapshot are gone
by design, and minute rows beyond 90 days are gone as well. The web UI's
time-range picker already knows which tier to query for a given range, so a
freshly restored DB works immediately without a rebuild step.

**`coldtrace-maintenance.timer` (daily at 04:15 local, `RandomizedDelaySec=15min`)**

Runs [scripts/coldtrace-retention.sh](../scripts/coldtrace-retention.sh),
which deletes `readings` older than `KEEP_DAYS` (default **180**, override
via `/etc/homelab/coldtrace-retention.env`) and then runs plain `VACUUM
(ANALYZE)`. `VACUUM FULL` is deliberately avoided: it rewrites the whole
table and holds an exclusive lock; plain `VACUUM` marks pages reusable
without blocking writers so the table converges to a steady size.

**`alerts` are never pruned.** They are the excursion history, they are
tiny, and `alerts.deviceId` references `devices`, not `readings`, so
pruning readings cannot cascade into alerts. Deleting alerts would erase
the record of every out-of-spec event, which is the whole reason coldtrace
exists.

## 7. Certs + DNS

If public IP changed, wait for DDNS to catch up (a few minutes) or run
`sudo systemctl start homelab-ddns.service` once by hand.

Caddy will re-fetch certs from Let's Encrypt on first request. If you hit the LE rate
limit during testing, use the staging endpoint temporarily.

## 8. Enable everything on boot

```bash
sudo systemctl enable --now \
    postgresql redis-server \
    airmon-server airmon-agent \
    coldtrace-backend \
    caddy \
    homelab-ddns.timer
```

## 9. Verify

```bash
curl -I https://airmon.utoker.com
curl -I https://api.coldtrace.app
```

Both should return 200 with a valid cert.
