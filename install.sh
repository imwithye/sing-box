#!/usr/bin/env bash
# install.sh — one-line bootstrapper for the sing-box-ctl wrapper.
#
# Pipe via curl. Without flags, setup prompts for any missing fields;
# anything passed via flags is forwarded as SINGBOX_<VAR> env vars and
# pre-fills the corresponding setup prompt. See `--help` for the full list.

set -euo pipefail

REPO_OWNER="${SINGBOX_REPO_OWNER:-imwithye}"
REPO_NAME="${SINGBOX_REPO_NAME:-sing-box}"
REF="${SINGBOX_REF:-main}"
WRAPPER_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REF}/sing-box-ctl"
WRAPPER_BIN="/usr/local/bin/sing-box-ctl"

DOMAIN_ARG=""
EMAIL_ARG=""
TOKEN_ARG=""
SNI_ARG=""
TS_AUTHKEY_ARG=""
TS_HOSTNAME_ARG=""
TS_EXIT_NODE_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain=*)       DOMAIN_ARG="${1#*=}" ;;
    --domain)         shift; DOMAIN_ARG="${1:-}" ;;
    --email=*)        EMAIL_ARG="${1#*=}" ;;
    --email)          shift; EMAIL_ARG="${1:-}" ;;
    --token=*)        TOKEN_ARG="${1#*=}" ;;
    --token)          shift; TOKEN_ARG="${1:-}" ;;
    --sni=*)          SNI_ARG="${1#*=}" ;;
    --sni)            shift; SNI_ARG="${1:-}" ;;
    --ts-authkey=*)   TS_AUTHKEY_ARG="${1#*=}" ;;
    --ts-authkey)     shift; TS_AUTHKEY_ARG="${1:-}" ;;
    --ts-hostname=*)  TS_HOSTNAME_ARG="${1#*=}" ;;
    --ts-hostname)    shift; TS_HOSTNAME_ARG="${1:-}" ;;
    --ts-exit-node=*) TS_EXIT_NODE_ARG="${1#*=}" ;;
    --ts-exit-node)   shift; TS_EXIT_NODE_ARG="${1:-}" ;;
    -h|--help)
      cat <<USAGE
Usage:
  curl -fsSL .../install.sh | sudo bash
  curl -fsSL .../install.sh | sudo bash -s -- [flags]

Flags (all optional — missing values are prompted for interactively):
  --domain=DOMAIN        domain pointing at this VPS, DNS-only on Cloudflare
  --email=EMAIL          contact email for Let's Encrypt registration
  --token=TOKEN          Cloudflare API token (Zone.DNS:Edit + Zone.Zone:Read)
  --sni=SNI              REALITY camouflage destination (default www.apple.com)
  --ts-authkey=KEY       Tailscale pre-auth key — enables tailnet egress (optional)
  --ts-hostname=NAME     Tailnet hostname for this node (optional, defaults to first DNS label)
  --ts-exit-node=NAME    Tailnet exit node name or 100.x IP (optional, blank = direct routing)
USAGE
      exit 0
      ;;
    *) echo "install.sh: unknown arg: $1" >&2; exit 1 ;;
  esac
  shift
done

if [[ $EUID -ne 0 ]]; then
  echo "install.sh must run as root — pipe to: sudo bash" >&2
  exit 1
fi

for cmd in curl tar install systemctl; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "install.sh: $cmd not found in PATH" >&2
    exit 1
  }
done

tmp="$(mktemp)"
trap "rm -f '$tmp'" EXIT
curl -fsSL "$WRAPPER_URL" -o "$tmp"
install -m 0755 "$tmp" "$WRAPPER_BIN"

# Pass args through to `sing-box-ctl setup` via SINGBOX_* env vars.
export SINGBOX_DOMAIN="$DOMAIN_ARG"
export SINGBOX_ACME_EMAIL="$EMAIL_ARG"
export SINGBOX_CF_API_TOKEN="$TOKEN_ARG"
export SINGBOX_REALITY_DEST_SNI="$SNI_ARG"
export SINGBOX_TS_AUTH_KEY="$TS_AUTHKEY_ARG"
export SINGBOX_TS_HOSTNAME="$TS_HOSTNAME_ARG"
export SINGBOX_TS_EXIT_NODE="$TS_EXIT_NODE_ARG"

exec "$WRAPPER_BIN" setup
