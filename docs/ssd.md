# USB SSD: mount and move persistent data

The Pi's SD card is fine for the OS but Postgres will destroy it in 12-24 months of
continuous writes. A USB3 SATA SSD fixes that completely and also improves I/O for
airmon's SQLite. Do this before enabling Postgres or Redis.

Current disk: **Samsung 860 EVO 500 GB** (465.8 GiB usable, single GPT partition,
label `airmon-data`, mounted at `/srv/data`). Any modern USB3 SSD of similar size
would work identically; the walkthrough below does not assume this specific model.

Everything the Pi persists lives under a single mount point, `/srv/data`:

```
/srv/data/
├── airmon/          SQLite (buffer + server), owned by umut
├── postgresql/17/main/   Postgres cluster, owned by postgres:postgres, mode 0700
└── backups/         nightly dumps
```

## 1. Attach the drive

Plug the SSD into a **USB3 (blue) port** on the Pi. Confirm the kernel sees it:

```bash
lsblk
# expect a /dev/sda entry the size of your disk, with no mount
dmesg | tail -20
```

## 2. Format and mount

```bash
sudo mkfs.ext4 -L airmon-data /dev/sda1     # or /dev/sda if no partition table
sudo mkdir -p /srv/data
UUID=$(sudo blkid -s UUID -o value /dev/sda1)
echo "UUID=$UUID /srv/data ext4 defaults,noatime,nofail 0 2" \
    | sudo tee -a /etc/fstab
sudo mount -a
mount | grep /srv/data
```

Mount by UUID rather than LABEL: if a second labeled disk is ever plugged in, LABEL
becomes ambiguous. `noatime` reduces writes further. `nofail` prevents boot hanging
if the SSD is unplugged.

## 3. Create the data dirs

```bash
sudo mkdir -p /srv/data/{airmon,backups}
sudo chown -R umut:umut /srv/data/airmon /srv/data/backups
# postgres dir is created by the relocation step below and stays root/postgres owned.
```

## 4. Move airmon's SQLite over (before starting Postgres)

If airmon was previously running from `/home/umut/airmon-data/`, move it:

```bash
sudo systemctl stop airmon-agent airmon-server
sudo mv /home/umut/airmon-data/* /srv/data/airmon/
rmdir /home/umut/airmon-data
```

The systemd units in this repo point at `/srv/data/airmon/` via `AIRMON_DB_PATH`
and `AIRMON_BUFFER_DB`, so a reinstall of the units is all that's needed:

```bash
sudo cp ~/homelab/systemd/airmon-*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start airmon-server airmon-agent
journalctl -u airmon-agent -n 5 --no-pager   # samples should resume immediately
```

## 5. Relocate Postgres data to the SSD

Postgres on Debian initializes its cluster at `/var/lib/postgresql/17/main` on
install. Moving it to the SSD is a **manual runbook**, not automated by
`bootstrap-pi.sh`. Reason: bootstrap only touches `/etc`; if it patched
`data_directory` on a fresh install without also relocating the cluster, Postgres
would come up pointing at an empty directory and silently serve a zero-row
database. Better to keep this explicit.

Run the whole block below on a fresh Pi after `bootstrap-pi.sh` has installed
`postgresql-17`, before creating any databases.

```bash
# Stop everything that could hold a Postgres connection.
sudo systemctl stop postgresql@17-main

# Copy the freshly-initialized cluster onto the SSD, preserving perms + xattrs.
# Trailing slash on the source is intentional (copy contents, not the dir).
sudo rsync -aHAX /var/lib/postgresql/ /srv/data/postgresql/

# Verify ownership + mode came across correctly. main/ MUST be postgres:postgres 0700
# or Postgres will refuse to start.
sudo ls -ld /srv/data/postgresql/17/main
#   expect: drwx------ ... postgres postgres ...

# Repoint the cluster.
sudoedit /etc/postgresql/17/main/postgresql.conf
#   set: data_directory = '/srv/data/postgresql/17/main'
#
# While in there, tune for Pi 4 (4 GB RAM, shared with other apps):
#   shared_buffers = 256MB
#   max_connections = 20
#   effective_cache_size = 1GB

# A drop-in in this repo (systemd/postgresql@17-main.service.d/ssd-mount.conf)
# adds RequiresMountsFor=/srv/data/postgresql/17/main so Postgres won't try to
# start before the SSD is mounted. bootstrap-pi.sh installs it.
sudo systemctl daemon-reload
sudo systemctl start postgresql@17-main

# Confirm Postgres is reading from the new location.
sudo -u postgres psql -tAc 'SHOW data_directory;'
#   expect: /srv/data/postgresql/17/main
```

Once confirmed, the old `/var/lib/postgresql/17/main` can be left alone as a
rollback path, or removed with `sudo rm -rf /var/lib/postgresql/17/main` after a
day of clean operation. The `postgresql.conf` edit lives only on the Pi; there is
no repo counterpart, on purpose (see the reason above).

## 6. Sanity check on reboot

```bash
sudo reboot
# after it comes back:
mount | grep /srv/data
systemctl status airmon-agent airmon-server postgresql@17-main --no-pager -n 3
```

All three should be running. If postgres refuses to start, check
`/var/log/postgresql/postgresql-17-main.log`. The two usual causes are (a) the
data dir owner/mode drifted from `postgres:postgres` 0700, or (b) the SSD didn't
mount in time and `RequiresMountsFor` wasn't installed.
