# DNS at Porkbun

Both `utoker.com` and `coldtrace.app` are registered at Porkbun and use Porkbun's
nameservers.

## A records the Pi needs

Add these once, in the Porkbun UI (Domain Management → DNS Records):

| Type | Host  | Answer            | TTL |
|------|-------|-------------------|-----|
| A    | airmon | `<Pi public IP>` | 300 |
| A    | api   | `<Pi public IP>`  | 300 |

The first is on `utoker.com`, the second on `coldtrace.app`. TTL 300 s so DDNS can flip
the record on IP change without a long stale window.

Left untouched:
- `utoker.com` apex A record → Vercel
- `coldtrace.app` apex A record → Vercel

## API access for DDNS

Residential IP can rotate. `homelab-ddns.timer` runs `scripts/update-ddns.sh` every
5 minutes to keep both A records aligned with the Pi's current public IP via Porkbun's
REST API.

**One-time setup:**

1. **Enable API per domain.** In Porkbun UI:
   *Domain Management* → click each domain → *API ACCESS* → toggle ON.
   Both `utoker.com` and `coldtrace.app` need it.

2. **Generate an API key pair** at
   [porkbun.com/account/api](https://porkbun.com/account/api).
   You get two values, both required:
   - `API Key` (starts `pk1_...`)
   - `Secret API Key` (starts `sk1_...`)

3. **Store the keys on the Pi**, `mode 0600`, owner `root`:

   ```bash
   sudo mkdir -p /etc/homelab
   sudo tee /etc/homelab/porkbun.env >/dev/null <<'EOF'
   PORKBUN_API_KEY=pk1_your_key_here
   PORKBUN_SECRET=sk1_your_secret_here
   EOF
   sudo chmod 600 /etc/homelab/porkbun.env
   sudo chown root:root /etc/homelab/porkbun.env
   ```

4. **Enable the timer:**

   ```bash
   sudo systemctl enable --now homelab-ddns.timer
   ```

5. **Verify:** run the script once by hand, watch the journal.

   ```bash
   sudo systemctl start homelab-ddns.service
   journalctl -u homelab-ddns.service -n 20 --no-pager
   ```

   First run should say `airmon.utoker.com: already <ip>` (or update it). Repeated runs
   are silent on stable IP.

The key file is NOT in git and never leaves the Pi. If the Pi is rebuilt, recreate
the file from your password manager.
