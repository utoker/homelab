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

## Cloudflare in front

`airmon.utoker.com` and `api.coldtrace.app` are both proxied by Cloudflare
(orange-cloud). That gives us edge TLS termination, DDoS absorption at the
edge, and origin-IP hiding for free. See [dns.md](dns.md) for how the records
are configured and why the two apex records stay grey-cloud.

The Pi still runs its own Let's Encrypt certs behind Cloudflare (SSL/TLS mode
is Full/strict), so a direct request to the origin IP would still get a valid
cert. Cloudflare is a preference, not a hard dependency.

## What we deliberately do NOT do

- **No app-level auth on airmon.** User explicitly picked "public" for the dashboard.
- **No rate limiting on GET endpoints.** Caddy would need a plugin; Cloudflare's
  default rate limits at the edge are enough for a homelab until abuse actually shows up.
- **No WAF rules configured on Cloudflare.** The zone is on the free plan with
  default managed rules only. If a real attack ever materializes, tighten the
  WAF (or drop in [caddy-security](https://github.com/greenpau/caddy-security)
  at the origin).
- **No 2FA on SSH.** Key + fail2ban is the standard bar for a homelab Pi.

## When something looks wrong

Quick triage:

```bash
sudo journalctl -f -u caddy               # traffic in real time
sudo journalctl -f -u ssh                 # ssh attempts (also in /var/log/auth.log)
sudo fail2ban-client status               # who's currently banned
sudo ufw status verbose                   # firewall state
```
