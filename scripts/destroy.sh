#!/usr/bin/env bash
# Tear down everything in Azure. The VPN gateway bills by the hour,
# so run this as soon as you've finished testing.
set -euo pipefail

RG="${RG:-rg-s2s-vpn-lab}"

read -r -p "Delete resource group '${RG}' and everything in it? [y/N] " ans
[[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

az group delete --name "$RG" --yes --no-wait
echo "Deletion started. Check with: az group exists --name ${RG}"
echo "Remember to remove the IPsec config from the MikroTik too (see README)."
