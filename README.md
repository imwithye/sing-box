# sing-box on a Singapore VPS, for Shanghai

A minimal-exposure sing-box deployment optimised for **Shanghai → Singapore**
access from iOS Shadowrocket. Two protocols share a single port for
redundancy:

| Transport | Port    | Protocol                   | Camouflage                             |
|-----------|---------|----------------------------|----------------------------------------|
| TCP       | 443     | VLESS + Vision + REALITY   | impersonates `www.apple.com` (default) |
| UDP       | 443     | Hysteria2 + ACME (CF DNS-01) | salamander obfs, real Let's Encrypt cert |

Only `443/tcp` and `443/udp` are exposed. No admin UI, no dashboard, no
extra ports. Hysteria2 fetches its certificate via Cloudflare DNS-01, so
even port 80 stays closed.

## What gets installed

`singbox` is a single bash script that drives the official sing-box
release binary under systemd. No Docker, no Go runtime, no compose
plugin.

```
/usr/local/bin/singbox          wrapper script (this repo)
/usr/local/bin/sing-box         upstream binary (downloaded by `install`)
/etc/systemd/system/sing-box.service
/etc/sing-box/.env              secrets (mode 0600)
/etc/sing-box/config.json       rendered sing-box config (0640)
/opt/sing-box/cache/            ACME certs + sing-box runtime state
/opt/sing-box/client/           subscription.{txt,b64} (share output)
```

Both directories can be relocated via `$SINGBOX_CONFIG_DIR` and
`$SINGBOX_DATA_DIR`. All commands except `help` require root.

## One-line install

```bash
curl -fsSL https://raw.githubusercontent.com/imwithye/sing-box/main/install.sh | sudo bash
```

That's the whole bootstrap. It will:

1. Enable TCP BBR (`/etc/sysctl.d/99-bbr.conf`).
2. Configure UFW: `deny in / allow out`, plus `22/tcp + 443/tcp + 443/udp`.
3. Download the latest sing-box release for your arch
   (`linux-amd64`/`arm64`) into `/usr/local/bin/sing-box`.
4. Install the systemd unit + enable it.
5. Drop a `/etc/sing-box/.env` template (or, if you pre-seeded it via
   cloud-init, generate the missing secrets and start the service).

After installation:

```bash
sudo vim /etc/sing-box/.env       # set DOMAIN, ACME_EMAIL, CF_API_TOKEN
sudo singbox init                 # generate REALITY/Hy2 secrets (idempotent)
sudo singbox up                   # render config + (re)start service
sudo singbox logs                 # follow journald output
```

## cloud-init

You can do the entire deployment from a fresh VPS with a single
cloud-init `user-data`:

```yaml
#cloud-config
write_files:
  - path: /etc/sing-box/.env
    permissions: '0600'
    content: |
      DOMAIN=teleport.example.com
      ACME_EMAIL=you@example.com
      CF_API_TOKEN=<cloudflare token with Zone.DNS:Edit + Zone.Zone:Read>
      REALITY_DEST_SNI=www.apple.com
      REALITY_DEST_PORT=443
runcmd:
  - curl -fsSL https://raw.githubusercontent.com/imwithye/sing-box/main/install.sh | bash
```

The installer notices the pre-seeded `.env`, fills in REALITY/Hy2
secrets, validates the config, and starts the service. Once cloud-init
is done you can `sudo singbox share` over SSH to grab the subscription.

## Day-to-day

Six commands, all root-only:

```
install   one-shot: BBR+UFW + sing-box binary + systemd unit + wrapper
setup     re-run host prep only (BBR + UFW)
init      fill missing secrets in /etc/sing-box/.env
up        render config + (re)start service
down      stop service
logs      journalctl -fu sing-box
status    systemctl status sing-box
share     print links + QR; write /opt/sing-box/client/subscription.{txt,b64}
upgrade   pull latest sing-box release + restart
```

Updating sing-box: `sudo singbox upgrade`. Updating the wrapper itself:
`curl -fsSL .../install.sh | sudo bash` again — `install` is idempotent.

If you change `VLESS_UUID`, `REALITY_*`, or `HYSTERIA2_*` in `.env`,
every existing client must be re-imported. Treat `/etc/sing-box/.env`
like a private key — it is the entire trust root.

## Hand off to Shadowrocket

```bash
sudo singbox share                # prints links + QR + writes subscription.{txt,b64}
```

Two ways to use the output:

- **One-off import**: scan the QR codes printed in your terminal (needs
  `qrencode` — `apt install qrencode`) or paste the printed links into
  Shadowrocket → Add Server. Group them as `url-test` on the phone for
  automatic failover.
- **Subscribe URL**: host `/opt/sing-box/client/subscription.b64`
  somewhere with an unguessable URL (e.g.
  `gh gist create --secret /opt/sing-box/client/subscription.b64`) and
  point Shadowrocket → Subscribe at the file's Raw URL. Re-run `sudo
  singbox share` and update the host file to push new creds to all
  devices. Treat the URL like a credential.

## Why these choices

- **VLESS+REALITY on TCP/443** — best stealth available against active
  probing. From an outside observer port 443 looks identical to the real
  apple.com TLS handshake; without the right `short-id` + `pbk`, the
  server falls back to proxying to the real site.
- **Hysteria2 on UDP/443** — when TCP is being throttled or has high
  RTT/loss (typical Shanghai evenings), QUIC pulls far ahead. The
  salamander obfs scrambles QUIC's distinctive handshake so it doesn't
  pattern-match QUIC blocking rules.
- **One port, two transports** — outbound network observers see only
  443/tcp + 443/udp. Anything else is a port scan against a closed port.
- **ACME via DNS-01** — no inbound HTTP/80 needed, ever.
- **Upstream binary + systemd, no Docker** — no daemon to keep alive,
  `journalctl` for logs, capability-bounded service hardening from the
  unit, atomic upgrades via `singbox upgrade`.

## Files

```
.
├── install.sh        # one-line curl-pipeable bootstrapper
├── singbox           # the wrapper (also self-installs to /usr/local/bin/)
└── README.md
```
