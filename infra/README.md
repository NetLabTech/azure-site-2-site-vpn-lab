# infra — Bicep version

I built the lab by hand in the portal so I'd understand every piece. This folder is the same Azure design written as **Bicep** (Microsoft's infrastructure-as-code language), so it can be rebuilt with one command and torn down just as easily.

It creates the same things: VNet with a workload subnet and a /27 GatewaySubnet, an NSG, a VpnGw1AZ gateway with a zone-redundant public IP, the local network gateway, the connection with the same custom IPsec policy, and a private-only Ubuntu VM.

The names follow a slightly tidier `s2slab-…` convention than the portal build did.

## Deploy

```bash
az login
ONPREM_PUBLIC_IP=<your public IP> ./scripts/deploy.sh
```

- The pre-shared key is generated for you and saved to `.psk`, which is git-ignored
- Your SSH public key is read from `~/.ssh/id_ed25519.pub`
- Secrets are passed in at deploy time through environment variables, so nothing sensitive is in `main.bicepparam`

## Tear down

```bash
./scripts/destroy.sh
```

## Things to check first

- Region: `uksouth` by default. New subscriptions can have region restrictions, see [troubleshooting](../08-Troubleshooting/README.md)
- VM size: `Standard_D2als_v6` by default. If you have B-series quota, `Standard_B2ats_v2` is much cheaper
