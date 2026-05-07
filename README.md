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
      [--sni=www.apple.com]
```

Either way the installer:

1. Enables TCP BBR (`/etc/sysctl.d/99-bbr.conf`).
2. Configures UFW: `deny in / allow out`, plus `22/tcp + 443/tcp + 443/udp`.
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

## Commands

Eight commands, all root-only:

```
setup          install everything (idempotent — also re-pulls the wrapper +
               regenerates only-empty secrets; auto-runs `up` if env is complete)
up             render config + (re)start service
down           stop service
logs           journalctl -fu sing-box
status         systemctl status sing-box
share [label]  print share links + QR codes; write subscription.{txt,b64}
upgrade        pull the latest sing-box release + restart
purge          tear down the deployment (service + binaries + config + 443 ufw rules)
```

## On-disk layout

```
/usr/local/bin/sing-box-ctl     this wrapper
/usr/local/bin/sing-box         upstream binary (downloaded by `setup`)
/etc/systemd/system/sing-box.service
/etc/sing-box/env               secrets (mode 0600)
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
