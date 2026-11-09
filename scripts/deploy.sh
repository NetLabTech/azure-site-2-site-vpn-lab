#!/usr/bin/env bash
# Deploy the Azure side of the site-to-site VPN lab.
# Usage: ./scripts/deploy.sh
# Requires: Azure CLI (az login done), an SSH key at ~/.ssh/id_ed25519.pub
set -euo pipefail

RG="${RG:-rg-s2s-vpn-lab}"
LOCATION="${LOCATION:-uksouth}"
SSH_KEY_FILE="${SSH_KEY_FILE:-$HOME/.ssh/id_ed25519.pub}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- On-prem public IP -------------------------------------------------------
if [[ -z "${ONPREM_PUBLIC_IP:-}" ]]; then
  ONPREM_PUBLIC_IP="$(curl -fsS https://api.ipify.org)"
  echo "Detected home public IP: ${ONPREM_PUBLIC_IP}"
  echo "  -> Check this matches the WAN IP on your MikroTik (CGNAT check!)"
fi
export ONPREM_PUBLIC_IP

# --- Pre-shared key ----------------------------------------------------------
if [[ -z "${VPN_PSK:-}" ]]; then
  VPN_PSK="$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)"
  PSK_FILE="${REPO_ROOT}/.psk"           # git-ignored
  umask 077 && printf '%s\n' "$VPN_PSK" > "$PSK_FILE"
  echo "Generated a new pre-shared key and saved it to .psk (git-ignored)."
fi
export VPN_PSK

# --- SSH key -----------------------------------------------------------------
if [[ ! -f "$SSH_KEY_FILE" ]]; then
  echo "No SSH key at $SSH_KEY_FILE - create one with: ssh-keygen -t ed25519" >&2
  exit 1
fi
export SSH_PUBLIC_KEY="$(cat "$SSH_KEY_FILE")"

# --- Deploy ------------------------------------------------------------------
echo "Creating resource group ${RG} in ${LOCATION}..."
az group create --name "$RG" --location "$LOCATION" \
  --tags project=azure-s2s-vpn-lab environment=lab -o none

echo "Deploying infrastructure (the VPN gateway takes ~30-45 min)..."
az deployment group create \
  --resource-group "$RG" \
  --name s2s-vpn-lab \
  --parameters "${REPO_ROOT}/infra/main.bicepparam" \
  --query "properties.outputs" -o table

echo
echo "Done. Next: put the VPN gateway public IP and the PSK into"
echo "mikrotik/ipsec-azure.rsc and import it on the router."
