# homelab

Deployment orchestration for personal projects self-hosted on a Raspberry Pi 4 at home.

Two apps are served publicly with HTTPS from the Pi:

- **[airmon](https://github.com/utoker/airmon)** — air quality monitor
  - Sensor agent reads three environmental sensors every 5 s
  - FastAPI backend + SQLite + Vite React SPA (served same-origin)
  - Public URL: `https://airmon.utoker.com`

- **[coldtrace](https://github.com/utoker/coldtrace)** — cold-chain monitoring
  - Next.js frontend on Vercel (`https://coldtrace.app`)
  - GraphQL backend (Apollo/Express) on the Pi
  - Public URL: `https://api.coldtrace.app`

## Topology

```
   Internet (HTTPS)
         │
         ├── Vercel Edge ──►  coldtrace.app  (Next.js frontend)
         │                     │
         │                     ▼ Apollo Client → api.coldtrace.app/graphql
         │
         └── Spectrum residential router :80,443 forward to Pi
                   │
                   ▼
   ┌──────────────────── Pi 4 (4 GB, 24/7) ──────────────┐
   │                                                     │
   │  Caddy (reverse proxy + auto Let's Encrypt)         │
   │    airmon.utoker.com  → 127.0.0.1:8000              │
   │    api.coldtrace.app  → 127.0.0.1:4000              │
   │                                                     │
   │  airmon-agent.service       samples every 5 s       │
   │  airmon-server.service      uvicorn :8000           │
   │  coldtrace-backend.service  apollo :4000            │
   │  postgresql@17-main.service data on SSD             │
   │  redis-server.service                               │
   │  homelab-ddns.timer         Porkbun DDNS every 5 min│
   │                                                     │
   │  /mnt/ssd/postgres/         Postgres data           │
   │  /mnt/ssd/airmon-data/      SQLite (buffer + server)│
   │  /mnt/ssd/backups/          nightly dumps           │
   │                                                     │
   └─────────────────────────────────────────────────────┘
```

## Layout

```
homelab/
├── README.md              this file
├── caddy/Caddyfile        both hosts, reverse proxy
├── systemd/               all unit files, symlinked or copied to /etc/systemd/system/
├── scripts/               deploy, backup, DDNS helpers
└── docs/                  step-by-step setup for each subsystem
```

## Setup docs

- [docs/ssd.md](docs/ssd.md) — mount the USB SSD and relocate Postgres + SQLite onto it
- [docs/dns.md](docs/dns.md) — Porkbun A records and API access
- [docs/security.md](docs/security.md) — ufw, fail2ban, unattended-upgrades
- [docs/recovery.md](docs/recovery.md) — rebuild the Pi from scratch

## Secrets

Never committed. Live on the Pi only, `mode 0600`, owner `root`:

- `/etc/homelab/porkbun.env` — Porkbun API keys for DDNS
- `/home/umut/coldtrace/apps/backend/.env` — DB / Redis URLs, GraphQL secrets

## One-time bootstrap

After a fresh Pi OS install and the SSH key + Tailscale-or-whatever access:

```bash
git clone https://github.com/utoker/homelab ~/homelab
sudo ~/homelab/scripts/bootstrap-pi.sh
```

Then follow [docs/ssd.md](docs/ssd.md) to attach the USB SSD and relocate data.

## Cost

- **One-time:** ~$25 (240 GB USB3 SATA SSD).
- **Ongoing:** $0. Domains and Vercel free tier remain elsewhere.
