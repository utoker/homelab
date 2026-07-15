# USB SSD: mount and move persistent data

The Pi's SD card is fine for the OS but Postgres will destroy it in 12-24 months of
continuous writes. A cheap USB3 SATA SSD (~$25 for 240 GB) fixes that completely and
also improves I/O for airmon's SQLite. Do this before enabling Postgres or Redis.

## 1. Attach the drive

Plug the SSD into a **USB3 (blue) port** on the Pi. Confirm the kernel sees it:

```bash
lsblk
# expect a /dev/sda entry ~240 GB with no mount
dmesg | tail -20
```

## 2. Format and mount

```bash
sudo mkfs.ext4 -L airmondata /dev/sda1     # or /dev/sda if no partition table
sudo mkdir -p /mnt/ssd
echo 'LABEL=airmondata /mnt/ssd ext4 defaults,noatime,nofail 0 2' \
    | sudo tee -a /etc/fstab
sudo mount -a
mount | grep /mnt/ssd
```

`noatime` reduces writes further. `nofail` prevents boot hanging if the SSD is
unplugged.

## 3. Create the data dirs

```bash
sudo mkdir -p /mnt/ssd/{postgres,airmon-data,backups}
sudo chown -R umut:umut /mnt/ssd/airmon-data /mnt/ssd/backups
# postgres dir stays root-owned; postgres user will take it in step 5
```

## 4. Move airmon's SQLite over (before starting Postgres)

Airmon is already running from `/home/umut/airmon-data/`. Move it:

```bash
sudo systemctl stop airmon-agent airmon-server
sudo mv /home/umut/airmon-data/* /mnt/ssd/airmon-data/
rmdir /home/umut/airmon-data
```

The systemd units in this repo already point at `/mnt/ssd/airmon-data/`, so a
reinstall of the units is all that's needed:

```bash
sudo cp ~/homelab/systemd/airmon-*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start airmon-server airmon-agent
journalctl -u airmon-agent -n 5 --no-pager   # samples should resume immediately
```

## 5. Relocate Postgres data to the SSD

Only do this if Postgres was already installed on the SD card and initialized.

```bash
sudo systemctl stop postgresql
sudo rsync -av /var/lib/postgresql/ /mnt/ssd/postgres/
```

Edit `/etc/postgresql/17/main/postgresql.conf`:

```conf
data_directory = '/mnt/ssd/postgres/17/main'

# tuning for Pi 4 (4 GB RAM, shared with other apps)
shared_buffers = 256MB
max_connections = 20
effective_cache_size = 1GB
```

Then:

```bash
sudo systemctl start postgresql
sudo -u postgres psql -c 'show data_directory;'   # should print /mnt/ssd/...
```

## 6. Sanity check on reboot

```bash
sudo reboot
# after it comes back:
mount | grep /mnt/ssd
systemctl status airmon-agent airmon-server postgresql --no-pager -n 3
```

All three should be running. If postgres refuses to start, check
`/var/log/postgresql/postgresql-17-main.log` — usually a permissions issue on the
moved data dir (must be owned by `postgres:postgres`, mode 0700).
