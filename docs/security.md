# Security hardening

Exposing a home Pi to the internet is fine as long as the basics are covered. This
list is minimal, not paranoid.

## SSH

- Key-only auth (already the case on this Pi).
- `PermitRootLogin no` (default on Debian Trixie — leave it).
- No `PasswordAuthentication yes` under any circumstance.

## Firewall

`bootstrap-pi.sh` sets these:

```
ufw allow OpenSSH
ufw allow 80,443/tcp
ufw enable
```

That's the whole public surface: SSH + Caddy. Everything else (Postgres, Redis,
airmon-server on 8000, coldtrace-backend on 4000) listens on `127.0.0.1` only and is
only reachable via Caddy.

## fail2ban

Default install ships an SSH jail. It bans an IP after 5 failed auths for 10 min.
Enough for personal use. Check with:

```bash
sudo fail2ban-client status sshd
```

## Unattended upgrades

`bootstrap-pi.sh` runs `dpkg-reconfigure unattended-upgrades`. Confirm what it
installs by looking at `/etc/apt/apt.conf.d/50unattended-upgrades` — by default only
the security suite auto-updates, which is what we want.

## What we deliberately do NOT do

- **No app-level auth on airmon.** User explicitly picked "public" for the dashboard.
- **No rate limiting on GET endpoints.** Caddy would need a plugin; not worth the
  complexity until abuse actually shows up.
- **No WAF.** No Cloudflare in front. If a real attack ever materializes, put Caddy
  behind Cloudflare (or drop in [caddy-security](https://github.com/greenpau/caddy-security)).
- **No 2FA on SSH.** Key + fail2ban is the standard bar for a homelab Pi.

## When something looks wrong

Quick triage:

```bash
sudo journalctl -f -u caddy               # traffic in real time
sudo journalctl -f -u ssh                 # ssh attempts (also in /var/log/auth.log)
sudo fail2ban-client status               # who's currently banned
sudo ufw status verbose                   # firewall state
```
