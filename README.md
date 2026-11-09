# homelab

Deployment orchestration for personal projects self-hosted on a Raspberry Pi 4 at home.

One app is served publicly with HTTPS from the Pi:

- **[airmon](https://github.com/utoker/airmon)** — air quality monitor
  - Sensor agent reads three environmental sensors every 5 s
  - FastAPI backend + SQLite + Vite React SPA (served same-origin)
  - Public URL: `https://airmon.utoker.com`

**ColdTrace is archived.** [coldtrace](https://github.com/utoker/coldtrace) was
archived off the Pi on 2026-11-09. Its services are stopped and disabled. The
final dump is in `/srv/data/archive/coldtrace/`, and restoring means git history
(this repo at `9a0f831`) plus that dump.

## Topology

```
   Internet (HTTPS)
         │
         ▼
   Cloudflare Edge (orange cloud proxy, hides origin IP)
                   │  airmon.utoker.com
                   ▼
             Spectrum residential router :80,443 forward to Pi
                   │
                   ▼
   ┌──────────────────── Pi 4 (4 GB, 24/7) ──────────────┐
   │                                                     │
   │  Caddy (reverse proxy + auto Let's Encrypt)         │
   │    airmon.utoker.com  → 127.0.0.1:8000              │
   │    :8081 (LAN, HTTP)  → GET /api/purifier/* only    │
   │                                                     │
   │  airmon-agent.service       samples every 5 s       │
   │  airmon-server.service      uvicorn :8000 (API + SPA)│
   │  AdGuardHome.service        LAN split-horizon DNS   │
   │  homeassistant (Docker)     :8123, LAN only         │
   │  homelab-ddns.timer         Cloudflare DDNS every 5 min│
   │  homelab-backup.timer       nightly 03:15, mirrors to R2│
   │  airmon-maintenance.timer   daily 03:45, tiered downsample│
   │                                                     │
   │  /srv/data/airmon/          SQLite (buffer + server)│
   │  /srv/data/backups/         nightly dumps (mirrored to R2)│
   │  /srv/data/archive/         final ColdTrace dump    │
   │  /srv/data/homeassistant/   HA config, not backed up│
   │                                                     │
   └─────────────────────────────────────────────────────┘
```

## Layout

```
homelab/
├── README.md              this file
├── caddy/Caddyfile        airmon host + LAN purifier listener, reverse proxy
├── homeassistant/         compose file, copied to /opt/homelab/homeassistant/
├── systemd/               all unit files, symlinked or copied to /etc/systemd/system/
├── journald/              drop-ins for /etc/systemd/journald.conf.d/ (persistent logs)
├── scripts/               deploy, backup, DDNS, healthcheck helpers
└── docs/                  step-by-step setup for each subsystem
```

## Setup docs

- [docs/ssd.md](docs/ssd.md) — mount the USB SSD and move SQLite onto it
- [docs/dns.md](docs/dns.md) — Cloudflare DNS + orange-cloud proxy, DDNS setup
- [docs/dns-lan.md](docs/dns-lan.md) — AdGuard Home split-horizon DNS on the LAN
- [docs/security.md](docs/security.md) — ufw, fail2ban, unattended-upgrades, Cloudflare edge
- [docs/recovery.md](docs/recovery.md) — rebuild the Pi from scratch, backups, R2 lifecycle, retention timers
- [docs/monitoring.md](docs/monitoring.md) — healthchecks.io dead-man's switch, persistent logs, what to do when it alerts

## Secrets

Never committed. Live on the Pi only, `mode 0600`, owner `root`:

- `/etc/homelab/cloudflare.env` — Cloudflare API token + zone/record IDs for DDNS
- `/etc/homelab/healthchecks.env` — healthchecks.io ping URL for the airmon check

## One-time bootstrap

After a fresh Pi OS install and the SSH key + Tailscale-or-whatever access:

```bash
git clone https://github.com/utoker/homelab ~/homelab
sudo ~/homelab/scripts/bootstrap-pi.sh
```

Then follow [docs/ssd.md](docs/ssd.md) to attach the USB SSD and relocate data.

## Cost

- **One-time:** USB3 SATA SSD (the current one is a 500 GB Samsung 860 EVO).
- **Ongoing:** $0. Domains and Vercel free tier remain elsewhere.
