# LAN split-horizon DNS via AdGuard Home

## Why this exists

The Sagemcom SAX1V1K router that Spectrum provides does not support NAT hairpin
(loopback). LAN devices trying to reach `airmon.utoker.com` or `api.coldtrace.app`
hit the Pi's public IP, the router refuses to loop it back, and the connection dies
with `ERR_CONNECTION_REFUSED`. External clients on the internet are unaffected.

The fix: run AdGuard Home on the Pi as an authoritative resolver for the LAN. It
forwards most queries to upstream resolvers (`1.1.1.1`, `9.9.9.9`), but overrides
`airmon.utoker.com` and `api.coldtrace.app` to `192.168.1.15` so LAN clients hit the
Pi directly with no hairpin needed.

## Topology

```
LAN device → asks Pi (192.168.1.15:53) for airmon.utoker.com
                → AdGuard rewrite → returns 192.168.1.15
                → LAN device connects directly to Pi over LAN
                → Caddy serves valid TLS cert (issued for airmon.utoker.com)

External device → asks Porkbun for airmon.utoker.com
                → returns 173.169.196.172 (Pi's public IP, kept in sync by DDNS)
                → traffic hits Spectrum router → forwarded to Pi
```

## Install

Done once via the AdGuard official installer:
```bash
curl -sSL https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh \
    | sudo sh -s -- -v
```
Installs to `/opt/AdGuardHome/` as systemd service `AdGuardHome`. Bind config in
`/opt/AdGuardHome/AdGuardHome.yaml`. Not in git — contains admin bcrypt hash.

## DNS rewrites (the actual overrides)

Two entries in AdGuardHome.yaml under `dns.rewrites`:
```yaml
dns:
  rewrites:
    - domain: airmon.utoker.com
      answer: 192.168.1.15
    - domain: api.coldtrace.app
      answer: 192.168.1.15
```

Add more here if we add more services on the Pi in the future.

## Router DNS — Sagemcom SAX1V1K quirk (Spectrum default router)

The My Spectrum app exposes a "DNS Server" field under Services → Internet. Setting
Primary=`192.168.1.15` here is **cosmetic** — verified empirically 2026-07-15:
- The field does NOT change what the router advertises to DHCP clients (LAN clients
  keep getting `192.168.1.1` handed out as DNS)
- The field does NOT change what the router forwards to when acting as a DNS proxy
  (queries to `192.168.1.1` return the upstream Spectrum resolver's answer, not
  AdGuard's rewrite)

So the Spectrum app is a dead-end for LAN-wide AdGuard adoption on this router.

**Two options:**

### Option A: per-device static DNS (used today)

Set each LAN device's network adapter to use `192.168.1.15` as DNS statically and
disable IPv6 on the adapter (otherwise Windows/macOS prefer Spectrum's IPv6 DNS
advertised via RA). Example on Windows PowerShell (admin):

```powershell
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.1.15,1.1.1.1
Get-NetAdapterBinding -InterfaceAlias "Ethernet" -ComponentID ms_tcpip6 | Set-NetAdapterBinding -Enabled $false
ipconfig /flushdns
```

macOS: System Settings → Network → wifi → Details → DNS → add `192.168.1.15` at top.
iOS/Android: per-network wifi settings → DNS → Manual → `192.168.1.15`.

Downside: every device needs this. Fine for a solo user with 2-3 devices; painful
for a full household.

### Option B: bridge the Spectrum router, add own router (long-term proper fix)

Call Spectrum, ask them to put the SAX1V1K in bridge mode. Add a UniFi / OpenWrt
router downstream. That router advertises `192.168.1.15` as DNS via DHCP properly.
One-time cost, cleanest solution. Not urgent.


## Verification

From any LAN client:
```bash
dig airmon.utoker.com    # should return 192.168.1.15
dig api.coldtrace.app    # should return 192.168.1.15
dig google.com           # should resolve normally (proves upstream works)
```

Open `https://airmon.utoker.com` in a LAN browser: dashboard loads with valid cert.

## Admin UI

AdGuard admin: `http://192.168.1.15:3000` (LAN only, not exposed externally).
Credentials in the operator's password manager. Only used to add new rewrites or
check query logs.

## Backup / recovery

`/opt/AdGuardHome/AdGuardHome.yaml` contains all config (including bcrypt-hashed
admin password). Include in the nightly backup script or copy it after any config
change:
```bash
sudo cp /opt/AdGuardHome/AdGuardHome.yaml /mnt/ssd/backups/adguard-$(date -Iseconds).yaml
```

On rebuild: reinstall AdGuard via the same installer script, stop the service,
drop the backed-up yaml into `/opt/AdGuardHome/`, start the service. Wizard is
skipped because the config already has a `users` section.
