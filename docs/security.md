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
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow from 192.168.1.0/24 to any port 53                                  # AdGuard DNS
ufw allow from 192.168.1.0/24 to any port 3000 proto tcp                      # AdGuard admin
ufw allow from 192.168.1.0/24 to any port 8081 proto tcp                      # airmon purifier API
ufw enable
```

That's the whole public surface: SSH + Caddy on 80/443. Everything else (airmon-server
on 8000) listens on `127.0.0.1` only and is only reachable via Caddy.

LAN only: AdGuard (53, 3000) and Caddy's plain-HTTP listener on 8081. The purifier
ESP32s poll `GET /api/purifier/{name}/target` there, so fan control works without
TLS or internet. Caddy proxies only `GET /api/purifier/*` from `192.168.1.0/24` on
that port and returns 404 for everything else.

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

`airmon.utoker.com` is proxied by Cloudflare
(orange-cloud). That gives us edge TLS termination, DDoS absorption at the
edge, and origin-IP hiding for free. See [dns.md](dns.md) for how the records
are configured and why the two apex records stay grey-cloud.

The Pi still runs its own Let's Encrypt certs behind Cloudflare (SSL/TLS mode
is Full/strict), so a direct request to the origin IP would still get a valid
cert. Cloudflare is a preference, not a hard dependency.

## airmon's public site is read-only

`https://airmon.utoker.com` answers `GET`/`HEAD` only under `/api`; any other
method on `/api` or `/api/*` gets a 404 from Caddy before it reaches the app.
The rule lives in the Caddyfile, so it applies whether the request comes
through Cloudflare or straight to the origin IP.

Why: `POST /api/readings` has no auth, and readings now drive the purifier
fans (airmon phase 6), so anyone on the internet could have faked air quality
and spun the fans up or down. Nothing legitimate writes through the public
site. The Pi agent posts to `http://127.0.0.1:8000/api` directly
(`AIRMON_SERVER_URL`), and the purifier ESP32s only `GET` via the LAN listener
on 8081.

If a new writer ever needs the public site, give it auth in the app first;
don't loosen this rule.

## What we deliberately do NOT do

- **No app-level auth on airmon reads.** User explicitly picked "public" for the
  dashboard. Writes are blocked at Caddy instead (see above).
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
