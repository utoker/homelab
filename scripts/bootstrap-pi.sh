#!/usr/bin/env bash
# One-time Pi setup. Idempotent-ish: safe to re-run, but a fresh Pi is the
# primary target. Run as root: `sudo ~/homelab/scripts/bootstrap-pi.sh`.
#
# Assumes the OS is Raspberry Pi OS 64-bit (Debian Trixie or newer) and the
# `umut` user already exists with SSH access.

set -euo pipefail

log() { printf '\n== %s ==\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
    echo "run me with sudo" >&2
    exit 1
fi

HOMELAB_DIR=${HOMELAB_DIR:-/home/umut/homelab}

log "apt update + core packages"
apt-get update -qq
apt-get install -y --no-install-recommends \
    curl ca-certificates gnupg \
    git rsync jq \
    python3-venv python3-pip \
    i2c-tools \
    ufw fail2ban unattended-upgrades \
    caddy \
    postgresql-17 \
    redis-server

log "Node.js 22 via nodesource (Debian Trixie ships 20, pnpm >= 10 needs 22)"
if ! node --version 2>/dev/null | grep -q '^v22'; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
fi

log "pnpm"
npm install -g pnpm

log "user groups (dialout, i2c, gpio) for umut"
usermod -aG dialout,i2c,gpio umut || true

log "shared dirs (data mount is done separately in docs/ssd.md)"
mkdir -p /etc/homelab /opt/homelab
chown root:root /etc/homelab
chmod 0755 /etc/homelab

log "install homelab scripts into /opt/homelab so systemd units can find them"
install -d -m 0755 /opt/homelab
rsync -a --delete "$HOMELAB_DIR/scripts/" /opt/homelab/scripts/
chmod 0755 /opt/homelab/scripts/*.sh

log "install systemd units"
for unit in "$HOMELAB_DIR"/systemd/*.service "$HOMELAB_DIR"/systemd/*.timer; do
    [[ -e $unit ]] || continue
    install -m 0644 "$unit" /etc/systemd/system/
done
for dropin_dir in "$HOMELAB_DIR"/systemd/*.service.d; do
    [[ -d $dropin_dir ]] || continue
    dest=/etc/systemd/system/$(basename "$dropin_dir")
    install -d -m 0755 "$dest"
    for conf in "$dropin_dir"/*.conf; do
        [[ -e $conf ]] || continue
        install -m 0644 "$conf" "$dest/"
    done
done
systemctl daemon-reload

log "install Caddyfile"
install -m 0644 "$HOMELAB_DIR/caddy/Caddyfile" /etc/caddy/Caddyfile

log "ufw rules (SSH + Caddy public; DNS + AdGuard admin LAN-only)"
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp   comment 'Caddy HTTP + LE' >/dev/null
ufw allow 443/tcp  comment 'Caddy HTTPS'     >/dev/null
ufw allow from 192.168.1.0/24 to any port 53             comment 'AdGuard DNS (LAN only)'   >/dev/null
ufw allow from 192.168.1.0/24 to any port 3000 proto tcp comment 'AdGuard admin (LAN only)' >/dev/null
ufw --force enable

log "unattended-upgrades"
dpkg-reconfigure -f noninteractive unattended-upgrades || true

cat <<EOF

Bootstrap done. Next:
  1. Attach the USB SSD; follow docs/ssd.md.
  2. Create /etc/homelab/porkbun.env (see docs/dns.md), then:
       systemctl enable --now homelab-ddns.timer
  3. Deploy each app (see docs/recovery.md), then:
       systemctl enable --now airmon-server airmon-agent
       systemctl enable --now coldtrace-backend
  4. Add DNS A records at Porkbun, then:
       systemctl reload caddy    # certs auto-issued on first request

EOF
