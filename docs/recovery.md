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
# restore airmon SQLite:
cp /path/to/server-<stamp>.db /srv/data/airmon/server.db
cp /path/to/buffer-<stamp>.db /srv/data/airmon/buffer.db
sudo chown -R umut:umut /srv/data/airmon
```

## 5. Clone and set up each app

```bash
# airmon
git clone https://github.com/utoker/airmon ~/airmon-repo
mkdir -p ~/airmon ~/airmon-server ~/airmon-web
# create venvs
python3 -m venv ~/airmon/.venv
~/airmon/.venv/bin/pip install -r ~/airmon-repo/pi/requirements.txt
python3 -m venv ~/airmon-server/.venv
~/airmon-server/.venv/bin/pip install -r ~/airmon-repo/server/requirements.txt
# first deploy populates ~/airmon, ~/airmon-server, ~/airmon-web from the repo
~/homelab/scripts/deploy-airmon.sh

# coldtrace
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
