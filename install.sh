#!/usr/bin/env bash
# install.sh — one-line bootstrapper for the sing-box deployment.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/imwithye/sing-box/main/install.sh | sudo bash
#
# In cloud-init you can pre-seed /etc/sing-box/env (DOMAIN, ACME_EMAIL,
# CF_API_TOKEN at minimum) and the installer will run end-to-end:
# BBR + UFW + sing-box binary + systemd unit + secrets + service start.
#
# Without a pre-seeded env file it stops after installing the binary and
# leaves a /etc/sing-box/env template for you to fill in.

set -euo pipefail

REPO_OWNER="${SINGBOX_REPO_OWNER:-imwithye}"
REPO_NAME="${SINGBOX_REPO_NAME:-sing-box}"
REF="${SINGBOX_REF:-main}"
WRAPPER_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REF}/singbox"
WRAPPER_BIN="/usr/local/bin/singbox"

if [[ $EUID -ne 0 ]]; then
  echo "install.sh must run as root — pipe to: sudo bash" >&2
  exit 1
fi

for cmd in curl tar install systemctl; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "$cmd not found in PATH" >&2
    exit 1
  }
done

tmp="$(mktemp)"
trap "rm -f '$tmp'" EXIT
curl -fsSL "$WRAPPER_URL" -o "$tmp"

install -m 0755 "$tmp" "$WRAPPER_BIN"
exec "$WRAPPER_BIN" setup
