# DNS at Cloudflare

Both `utoker.com` and `coldtrace.app` are registered at Porkbun but use
**Cloudflare's nameservers** (`kehlani.ns.cloudflare.com`, `lee.ns.cloudflare.com`).
Porkbun stays the registrar (billing, WHOIS, transfer lock); Cloudflare hosts the
authoritative DNS and, for the Pi-served hostnames, proxies traffic through its
edge.

## Records per zone

Records marked **orange** are proxied through Cloudflare (edge TLS, WAF, hides
origin IP). Records marked **grey** are DNS-only.

**utoker.com**

| Type  | Name              | Content                | Proxy   | TTL  |
|-------|-------------------|------------------------|---------|------|
| A     | utoker.com        | 76.76.21.21            | grey    | 600  |
| A     | airmon.utoker.com | Pi public IP (DDNS)    | orange  | auto |
| CNAME | www.utoker.com    | cname.vercel-dns.com   | grey    | 600  |

**coldtrace.app**

| Type  | Name              | Content                                | Proxy   | TTL  |
|-------|-------------------|----------------------------------------|---------|------|
| A     | coldtrace.app     | 216.198.79.1                           | grey    | 600  |
| A     | api.coldtrace.app | Pi public IP (DDNS)                    | orange  | auto |
| CNAME | *.coldtrace.app   | 317302a78fda56d9.vercel-dns-017.com    | grey    | 600  |

The two apex A records and both Vercel-target records stay **grey** — Vercel
handles its own edge and proxying through Cloudflare would break its cert
provisioning.

## Zone-level settings

- **SSL/TLS mode**: Full (strict). Cloudflare validates the origin's Let's
  Encrypt cert. Anything less either breaks TLS or is insecure.
- **Always Use HTTPS**: on.

## DDNS

Residential IP can rotate. `homelab-ddns.timer` runs
[scripts/update-ddns.sh](../scripts/update-ddns.sh) every 5 minutes to keep the
two proxied A records (`airmon.utoker.com`, `api.coldtrace.app`) aligned with the
Pi's current public IP via Cloudflare's REST API.

The record content is the *origin* IP; Cloudflare terminates the client
connection at its edge and forwards to that IP. Clients never see the origin IP
directly.

### One-time setup

1. **Create a Cloudflare API token** at
   [dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens).
   Use "Create Custom Token" with least-privilege permissions:

   | Category | Permission | Level |
   |----------|------------|-------|
   | Zone | DNS | Edit |

   **Zone Resources**: Include → Specific zone → `utoker.com`, then Add more →
   Specific zone → `coldtrace.app`. Do NOT use "All zones" — the DDNS process
   should only be able to touch these two zones.

   **Client IP filter**: your home public IP. Set a long TTL (multi-year is fine
   with the IP filter; the practical blast radius is zero from anywhere else).

2. **Look up the zone and record IDs** so the script knows what to update.
   Any machine with the token works; example uses the Pi:

   ```bash
   TOKEN=<paste the token>
   for d in utoker.com coldtrace.app; do
     ZID=$(curl -sH "Authorization: Bearer $TOKEN" \
       "https://api.cloudflare.com/client/v4/zones?name=$d" \
       | jq -r '.result[0].id')
     echo "$d zone_id=$ZID"
     curl -sH "Authorization: Bearer $TOKEN" \
       "https://api.cloudflare.com/client/v4/zones/$ZID/dns_records?type=A" \
       | jq -r '.result[] | select(.proxied) | "  \(.name) record_id=\(.id)"'
   done
   ```

3. **Store the token and IDs on the Pi**, `mode 0600`, owner `root`:

   ```bash
   sudo mkdir -p /etc/homelab
   sudo tee /etc/homelab/cloudflare.env >/dev/null <<'EOF'
   CF_API_TOKEN=paste_token_here
   CF_ZONE_ID_UTOKER=paste_utoker_zone_id_here
   CF_RECORD_ID_AIRMON=paste_airmon_record_id_here
   CF_ZONE_ID_COLDTRACE=paste_coldtrace_zone_id_here
   CF_RECORD_ID_API=paste_api_record_id_here
   EOF
   sudo chmod 600 /etc/homelab/cloudflare.env
   sudo chown root:root /etc/homelab/cloudflare.env
   ```

4. **Enable the timer:**

   ```bash
   sudo systemctl enable --now homelab-ddns.timer
   ```

5. **Verify:** run once by hand, watch the journal.

   ```bash
   sudo systemctl start homelab-ddns.service
   journalctl -u homelab-ddns.service -n 20 --no-pager
   ```

   First run should say `airmon.utoker.com: already <ip>` (or update it). Repeated
   runs are silent on stable IP.

The key file is NOT in git and never leaves the Pi. If the Pi is rebuilt,
recreate it from your password manager.

## Nameserver history

- 2026-07-15: nameservers migrated from Porkbun (`*.ns.porkbun.com`) to Cloudflare
  (`kehlani.ns.cloudflare.com`, `lee.ns.cloudflare.com`) for both domains, to put
  Cloudflare's edge in front of the Pi-served hostnames. Porkbun remains the
  registrar.
