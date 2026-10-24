# Monitoring: healthchecks.io + persistent logs

On 2026-10-20 the airmon USB-SATA adapter appears to have hung, the Pi froze,
and it came back without its Wi-Fi config. Nothing noticed for ~4 days, and
because Raspberry Pi OS keeps logs in RAM only, there was no record of why.
This doc covers the two fixes: an outside alarm, and logs that survive a reboot.

## 1. healthchecks.io dead-man's switch

A Pi cannot report its own death, so the alarm lives outside the house. Every
15 minutes `homelab-healthcheck.timer` runs `scripts/healthcheck.sh`, which pings
healthchecks.io **only if**:

- a reading landed in `server.db` in the last 2 minutes (sensors, agent, server
  and SSD all working), and
- `https://airmon.utoker.com/api/health` returns 200 through Cloudflare (DNS,
  proxy, router port-forward and Caddy all working).

If either fails, the reason goes to the check's `/log` endpoint (visible in the
healthchecks.io event list) and no ping is sent. If pings stop for longer than
period + grace, healthchecks.io emails you. A dead Pi, a dead network, or a dead
house circuit all look the same from outside: silence, then an email.

### Setup

1. Create a free account at [healthchecks.io](https://healthchecks.io).
2. Add a check named `airmon`: **Simple** schedule, **Period 15 minutes**,
   **Grace 20 minutes**. Grace is longer than one period so a single blip (a
   deploy restarting the server mid-check) does not page you; a real outage
   alerts within ~35 minutes. Email alerts to the account address are on by
   default.
3. Copy its ping URL (`https://hc-ping.com/<uuid>`) and put it on the Pi:

   ```bash
   echo 'HC_PING_URL_AIRMON=https://hc-ping.com/<uuid>' | sudo tee /etc/homelab/healthchecks.env >/dev/null
   sudo chmod 600 /etc/homelab/healthchecks.env
   sudo chown root:root /etc/homelab/healthchecks.env
   ```

4. Enable the timer, then run once by hand:

   ```bash
   sudo systemctl enable --now homelab-healthcheck.timer
   sudo systemctl start homelab-healthcheck.service
   journalctl -u homelab-healthcheck.service -n 5 --no-pager
   ```

   Expect `ok (N readings in last 120s); pinged`, and the check turns green on
   the dashboard.

The ping URL is a secret in the weak sense (anyone holding it can fake "up"),
so it lives in `/etc/homelab/` and is included in the encrypted secrets tarball.

## 2. Persistent logs

Raspberry Pi OS ships `/usr/lib/systemd/journald.conf.d/40-rpi-volatile-storage.conf`
with `Storage=volatile`. `journald/90-homelab-persistent.conf` overrides it:
logs go to `/var/log/journal` on the SD card, capped at 500 MB, synced every
minute. They deliberately do **not** live on the SSD, because the SSD is one of
the things whose failure they need to record.

Read the boot before the current one (the one that crashed):

```bash
journalctl --list-boots
journalctl -b -1 -e            # end of the previous boot
journalctl -b -1 -k -p warning # kernel warnings/errors only
```

## 3. When the alert fires

1. `ssh airmon`. If it answers, read
   `journalctl -u homelab-healthcheck -n 5` for which condition failed.
2. If it does not answer on Wi-Fi, plug in Ethernet: the Pi auto-connects on
   `eth0` with no saved profile and gets a different DHCP address. Find it with
   the router's client list, or reach it with
   `ssh -o HostName=<ip> -o HostKeyAlias=192.168.1.15 airmon`.
3. If `lsblk` shows no `sda`, the USB-SATA adapter is likely wedged. Its own
   12 V brick keeps it powered across Pi reboots, so a Pi restart alone does
   not clear it. `sudo poweroff`, unplug the adapter's **brick** for 10
   seconds, plug it back in (blue LED on), then power the Pi back on.
4. Only pull the Pi's power if SSH is unreachable on both Wi-Fi and Ethernet.
   An unclean power cut is what can empty half-written config files.
