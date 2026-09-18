# sing-box-ctl

Bash wrapper that deploys [sing-box](https://github.com/SagerNet/sing-box)
on a single VPS as a systemd service:

- **VLESS + Vision + REALITY** on `443/tcp`, impersonating `www.apple.com`
- **Hysteria2 + salamander** on `443/udp`, with a real Let's Encrypt cert
  via Cloudflare DNS-01

No Docker, no Go runtime, no compose plugin — just bash + curl + systemd
+ the upstream sing-box release binary.

## Install

Interactive (prompts for domain / email / Cloudflare token):

```bash
curl -fsSL https://raw.githubusercontent.com/imwithye/sing-box/main/install.sh | sudo bash
```

One-shot (no prompts):

```bash
curl -fsSL https://raw.githubusercontent.com/imwithye/sing-box/main/install.sh \
  | sudo bash -s -- \
      --domain=teleport.example.com \
      --email=you@example.com \
      --token=<CLOUDFLARE_API_TOKEN> \
      [--sni=www.apple.com] \
      [--tailscale] \
      [--ts-authkey=<TAILSCALE_AUTH_KEY>] \
      [--ts-hostname=<TAILNET_HOSTNAME>]
```

Either way the installer:

1. Enables TCP BBR (`/etc/sysctl.d/99-bbr.conf`).
2. Installs `ufw` + `qrencode` + `jq` via apt, then configures UFW:
   `deny in / allow out`, plus `22/tcp + 443/tcp + 443/udp`.
   (`jq` patches in the Tailscale endpoint when enabled.)
3. Downloads the latest sing-box release for your arch
   (`linux-amd64`/`arm64`) into `/usr/local/bin/sing-box`.
4. Installs the systemd unit + enables it.
5. Writes `/etc/sing-box/env` (template, then prompts/fills the user
   fields) and generates REALITY + Hysteria2 secrets.
6. Renders `/etc/sing-box/config.json`, validates it, and starts the
   service.

The Cloudflare API token needs `Zone.DNS:Edit` + `Zone.Zone:Read` on the
zone for your domain. Make sure the DNS record is **DNS-only (gray
cloud)** — sing-box protocols don't pass through Cloudflare's CDN.

## Optional: Tailscale egress

Turn it on with `TS_ENABLED=yes` in `/etc/sing-box/env` (the `setup` /
`configure` prompt, or `--tailscale`). sing-box's built-in `tailscale`
endpoint then joins your tailnet and the rendered config auto-routes:

- IPv4 `100.64.0.0/10` and IPv6 `fd7a:115c:a1e0::/48` → tailscale endpoint
- DNS suffix `*.ts.net` (MagicDNS) → tailscale DNS server

So clients connected to sing-box can reach tailnet IPs / MagicDNS names
transparently. No `tailscaled` is installed — sing-box embeds tsnet
directly.

### Two ways to attach the node

**Login URL** (leave `TS_AUTH_KEY` blank):

```bash
sudo sing-box-ctl ts login     # prints https://login.tailscale.com/a/...
sudo sing-box-ctl ts status    # State: NeedsLogin → Running once approved
```

**Pre-auth key** (`TS_AUTH_KEY=`, `--ts-authkey=`): headless, no clicking.
Get one at <https://login.tailscale.com/admin/settings/keys> — a *reusable,
pre-approved* key fits a long-lived server.

### Switching tailnets

```bash
sudo sing-box-ctl ts logout    # leave the current tailnet, print a new login URL
```

`logout` deregisters the node upstream, clears `TS_AUTH_KEY` (a key only
ever works for the tailnet it came from), and immediately offers a fresh
login URL — so moving from one tailnet to another is one command plus one
click. The stale node stays listed in the old tailnet's admin console until
you delete it there.

Only one tailnet at a time: the wrapper renders a single `tailscale-ep`
endpoint. sing-box itself allows several, but every tailnet shares
`100.64.0.0/10` and `*.ts.net`, so they can't be told apart by route rules.

These commands talk to a loopback gRPC API service (`127.0.0.1:6756`,
secret in `API_SECRET`) that is rendered into `config.json` only while
`TS_ENABLED=yes` — the login state lives in the running process, not in the
config. Needs sing-box 1.14.0+.

Optional knobs (all skip-able with a blank prompt):

- `TS_HOSTNAME` — node name on the tailnet (defaults to the first DNS
  label of `DOMAIN`).
- `TS_EXIT_NODE` — name or `100.x` IP of a tailnet peer to route
  `tailscale-ep` traffic through. Empty means direct peer-to-peer.
- `/etc/sing-box/tsexit` — extra destinations to route through
  `tailscale-ep`. One entry per line, `#` for comments. Domains
  (`netflix.com`, `*.bbc.co.uk`) are suffix-matched; bare IPs become
  `/32` (v4) or `/128` (v6); CIDRs pass through. Generated empty by
  `setup`; re-read on every `up`.

## Commands

All root-only:

```
setup          install everything (idempotent — also re-pulls the wrapper +
               regenerates only-empty secrets; auto-runs `up` if env is complete)
configure      re-run the interactive prompts, then re-render + restart
up             render config + (re)start service
down           stop service
logs           journalctl -fu sing-box
status         systemctl status sing-box
share [label]  print share links + QR codes; write subscription.{txt,b64}
ts status      tailscale: backend state, tailnet, pending login URL
ts login       enable + attach this node (prints the login URL)
ts logout      leave the current tailnet, then offer a new login URL
upgrade        pull the latest sing-box release, offer the prompts, restart
purge          tear down the deployment (service + binaries + config + 443 ufw rules)
```

`update` is an alias for `upgrade`. Both ask *"review settings now?"* on a
TTY, which walks the same prompts as `configure` — so the routine visit to
the box (upgrade, retune, restart) is a single command.

## On-disk layout

```
/usr/local/bin/sing-box-ctl     this wrapper
/usr/local/bin/sing-box         upstream binary (downloaded by `setup`)
/etc/systemd/system/sing-box.service
/etc/sing-box/env               secrets (mode 0600)
/etc/sing-box/tsexit            extra tailscale-ep routes (0600, optional)
/etc/sing-box/config.json       rendered sing-box config (0640)
/etc/sing-box/cache/            ACME certs + sing-box runtime state
/etc/sing-box/client/           subscription.{txt,b64}
```

`$SINGBOX_CONFIG_DIR` relocates the entire `/etc/sing-box` tree.

## Hand off to a client

```bash
sudo sing-box-ctl share              # prints links + QR + writes subscription.{txt,b64}
```

- **One-off import**: scan the QR codes or paste the printed links into
  your client (Shadowrocket, sing-box, etc.). Group them as `url-test`
  for automatic failover.
- **Subscribe URL**: host `/etc/sing-box/client/subscription.b64` at an
  unguessable URL (e.g.
  `gh gist create --secret /etc/sing-box/client/subscription.b64`) and
  point the client → Subscribe at the file's Raw URL. Re-run
  `sudo sing-box-ctl share` and update the host file to push new creds
  to all devices. Treat the URL like a credential.

If you change `VLESS_UUID`, `REALITY_*`, or `HYSTERIA2_*` in
`/etc/sing-box/env`, every existing client must be re-imported. Treat
that file like a private key.

## Files

```
.
├── install.sh        # one-line curl-pipeable bootstrapper
├── sing-box-ctl      # the wrapper (self-installs to /usr/local/bin/)
└── README.md
```
