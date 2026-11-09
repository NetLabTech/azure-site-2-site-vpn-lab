# Azure Site-to-Site VPN Lab (Home Network ↔ Azure)

In this lab I connected my home network to Azure with a site-to-site IPsec VPN, the same kind of setup a small company uses to reach its cloud servers privately. On my side there's a MikroTik router sitting behind a Sky Hub (so double NAT). On the Azure side there's a VPN gateway and a small Linux VM with **no public IP**. When I could SSH into that VM from my Mac at home, I knew the tunnel was doing its job.

I've written it up as if it was a proposal for a real customer, then walked through how I actually built it, step by step with screenshots. I've also kept the problems I ran into, because a few of them took longer than the build itself.

**Skills shown:** Azure networking (VNets, subnets, GatewaySubnet) · VPN Gateway and Local Network Gateway · IPsec/IKEv2 with a custom crypto policy · MikroTik RouterOS IPsec · port forwarding through double NAT · NSGs and private-only VMs · Azure Policy, region and quota troubleshooting · tagging and cost control · Bicep (infrastructure as code).

## The scenario

A 20-person accountancy firm in Dublin (made up for the lab) is moving its line-of-business app server to Azure. Staff need to reach it from the office as if it was on the local network, and the server must **not** be exposed to the internet. They want it live quickly, on their existing broadband and router, for a predictable monthly cost.

My answer: an Azure VPN Gateway with a site-to-site IPsec tunnel to the office router. The full reasoning is in [01 — Planning and design](01-Planning-and-Design/README.md).

## Lab layout

![Architecture diagram](diagrams/architecture.svg)

| Thing | Value |
| --- | --- |
| Home LAN (behind the MikroTik) | `192.168.88.0/24` |
| MikroTik WAN (behind the Sky Hub) | `192.168.0.212` |
| Azure region | UK South (London) |
| Azure VNet | `Vnet_Lab`, `10.10.0.0/16` |
| Workload subnet | `Snet_workspace`, `10.10.1.0/24` (private subnet) |
| Gateway subnet | `GatewaySubnet`, `10.10.2.0/27` |
| VPN gateway | `VpnGwLab`, VpnGw1AZ, route-based |
| Test VM | `VmLab01`, Ubuntu 24.04, `10.10.1.4`, no public IP |
| Tunnel | IKEv2 · AES256 / SHA256 / DH14 · PFS2048 |

## Contents

1. [Planning and design](01-Planning-and-Design/README.md): the customer scenario, design decisions, security and cost estimate
2. [Azure virtual network](02-Azure-Virtual-Network/README.md): the VNet and both subnets, and why I ended up in UK South
3. [VPN gateway](03-VPN-Gateway/README.md): picking the SKU and deploying the gateway (the 45-minute wait)
4. [Local network gateway and connection](04-Local-Network-Gateway-and-Connection/README.md): telling Azure about my home network, plus the custom IPsec policy
5. [Test VM](05-Test-VM/README.md): a private-only Ubuntu VM, auto-shutdown and the quota surprises
6. [Home network: Sky Hub and MikroTik](06-Home-Network-Sky-Hub-and-MikroTik/README.md): port forwarding through double NAT and the RouterOS config
7. [Testing the tunnel](07-Testing-the-Tunnel/README.md): tunnel up, ping, SSH, and the traffic graphs
8. [Troubleshooting](08-Troubleshooting/README.md): everything that broke and how I fixed it
9. [Cost and cleanup](09-Cost-and-Cleanup/README.md): what it cost and how I tore it all down

There's also:
- [`infra/`](infra/): a Bicep version of the Azure side, so the whole thing can be rebuilt with one command
- [`mikrotik/`](mikrotik/): the RouterOS script for the tunnel (placeholders, no real IPs or keys) and a teardown script
- [`scripts/`](scripts/): deploy and destroy scripts for the Bicep version

## Highlight: getting through double NAT

My MikroTik doesn't sit on the internet directly, because it's behind the Sky Hub. So I forwarded UDP 500 and UDP 4500 on the Sky Hub to the MikroTik, locked down so that **only the Azure gateway's IP** is allowed in. I also had to tell the MikroTik to identify itself with my public IP instead of its private one, otherwise Azure doesn't recognise it. Once that was in, the tunnel came straight up. See [section 6](06-Home-Network-Sky-Hub-and-MikroTik/README.md).

## Results

- Tunnel **established** on the MikroTik and **Connected** in Azure
- Ping from my Mac to the VM: 4/4 replies, **0% loss, ~21 ms** (Dublin to London)
- **SSH** into a VM that has no public IP, which is the whole point
- Azure showed real traffic through the tunnel (~59 KiB in / 45 KiB out)

## Notes

- I built this through the Azure portal so I'd understand every piece. The Bicep in `infra/` is the repeatable version of the same design.
- This was a temporary lab. Everything was deleted afterwards so it wouldn't keep billing, and the MikroTik and Sky Hub rules were removed too.
- IPs, subscription IDs and keys are blurred or replaced with placeholders throughout.
