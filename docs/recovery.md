# Rebuild the Pi from scratch

If the SD card dies or someone rebuilds the Pi, this is the recovery order.

## 0. Prerequisites off-Pi

- A recent backup somewhere reachable (see `scripts/backup.sh`; ideally rsync'd off
  the Pi to another host or an S3 bucket).
- Porkbun API keys in your password manager.
- SSH pubkey ready to push to the fresh Pi.

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

## 6. Secrets

Recreate `/etc/homelab/porkbun.env` from your password manager
(see [docs/dns.md](dns.md)) and enable the DDNS timer.

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
