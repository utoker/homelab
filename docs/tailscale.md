# Tailscale: Home Assistant and ad blocking away from home

Tailscale puts the Pi and Umut's iPhone on a private network (a "tailnet"), so
the phone reaches LAN-only services from anywhere without opening router ports
or adding anything to Cloudflare. Two things use it:

- **Home Assistant** at `http://100.125.120.116:8123`. The HA iOS app's external
  URL points there.
- **AdGuard Home** as the phone's DNS whenever Tailscale is connected, so ads and
  trackers are blocked on cellular and other networks too.

The tailnet uses Apple sign-in, has MagicDNS on (suffix `taile9c216.ts.net`),
and runs on Tailscale's free personal plan. Set up 2026-11-10.

## Install on the Pi

Tailscale's own apt repo for Debian trixie:

```bash
curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg \
  | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list \
  | sudo tee /etc/apt/sources.list.d/tailscale.list
sudo apt-get update && sudo apt-get install -y tailscale
sudo tailscale up --hostname=airmon --accept-dns=false
```

`tailscale up` prints a login URL. Open it and sign in with the tailnet's Apple
account. The URL is single-use and claims the Pi for whoever opens it first, so
don't paste it anywhere shared.

`--accept-dns=false` matters: the Pi is the house's DNS server, so its own
resolver config must stay as it is, not point at Tailscale's.

Firewall: ufw decides what the tailnet can reach, as on the LAN. Only DNS and
Home Assistant are open on `tailscale0`; SSH is already open on every interface.

```
ufw allow in on tailscale0 to any port 53 comment 'AdGuard DNS (Tailscale)'
ufw allow in on tailscale0 to any port 8123 proto tcp comment 'Home Assistant (Tailscale)'
```

AdGuard already binds `0.0.0.0:53`, so it needs no change.

## Admin console settings (login.tailscale.com/admin)

- **Machines → airmon → Disable key expiry.** Without it the Pi drops off the
  tailnet every 180 days.
- **DNS → Nameservers → Custom → `100.125.120.116`**, with **Override local
  DNS** on. Every tailnet device then sends its DNS lookups to AdGuard.

Check from the Pi: `sudo tailscale dns status` lists `100.125.120.116` under
Resolvers, and `sudo tcpdump -n -i tailscale0 udp port 53` shows the phone's
queries arriving.

## On the iPhone

- Tailscale app signed in to the same account. Leave it connected all the time
  for ad blocking everywhere.
- HA app → Settings → Companion App → server: external URL
  `http://100.125.120.116:8123`; internal URL `http://192.168.1.15:8123` with the
  home Wi-Fi SSID.

If the Pi is down, the phone's DNS fails while Tailscale is connected, so
websites stop loading. Turn Tailscale off in the app until the Pi is back.

## After a rebuild

A fresh OS install is a new Tailscale machine with a new `100.x` address. After
`tailscale up`:

1. Remove the old `airmon` from the admin console and disable key expiry on the
   new one.
2. Update the DNS nameserver and the HA app's external URL to the new address.
3. Update this file.
