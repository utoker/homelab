# USB SSD: mount and move persistent data

The Pi's SD card is fine for the OS but continuous database writes will wear it out.
A USB3 SATA SSD fixes that completely and also improves I/O for airmon's SQLite. Do
this before starting airmon.

Current disk: **Samsung 860 EVO 500 GB** (465.8 GiB usable, single GPT partition,
label `airmon-data`, mounted at `/srv/data`). Any modern USB3 SSD of similar size
would work identically; the walkthrough below does not assume this specific model.

Everything the Pi persists lives under a single mount point, `/srv/data`:

```
/srv/data/
├── airmon/          SQLite (buffer + server), owned by umut
├── backups/         nightly dumps
├── archive/coldtrace/    final ColdTrace dump + env files, mode 0700, never pruned
└── postgresql/17/main/   stopped ColdTrace cluster, kept so the archive stays reversible
```

The last two exist only on the current SSD. A fresh disk does not need them.

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
```

## 4. Move airmon's SQLite over

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

## 5. Sanity check on reboot

```bash
sudo reboot
# after it comes back:
mount | grep /srv/data
systemctl status airmon-agent airmon-server --no-pager -n 3
```

Both should be running.
