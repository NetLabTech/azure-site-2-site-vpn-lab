# 01 — Planning and Design

Before building anything, I wrote this up the way I'd present it to a customer: what they need, what I'd recommend, and why.

---

## The customer

**Who:** a 20-person accountancy practice in Dublin (fictional).

**What's happening:** they're moving their main business application server to Azure. Staff work from the office and need to reach it, but the server must not be reachable from the internet.

**Requirements**
1. Office users reach the Azure server by its private IP, like it's on the office network
2. No public IPs on the server
3. Everything between the office and Azure is encrypted
4. Live in days, using the broadband and router they already have
5. A predictable, modest monthly cost

---

## What I recommended

A **site-to-site VPN**: an Azure VPN Gateway on one end and the office router on the other, with an IPsec tunnel between them over the normal internet connection.

In the lab, my home network plays the office and my MikroTik plays the office router.

---

## Design decisions

### Site-to-site VPN vs the alternatives

| Option | Would it fit? | Why / why not |
| --- | --- | --- |
| **Site-to-site VPN** ✅ | Yes | Encrypted over the existing broadband, live in a day, low fixed cost |
| ExpressRoute | Overkill | Private circuit with guaranteed bandwidth, but it needs a provider, takes weeks, and costs a lot more |
| Point-to-site VPN | Partly | Good for remote staff, but every laptop needs a VPN client and it doesn't connect the office as a whole |
| Azure Bastion only | Partly | Great for admin access to VMs, but it doesn't give the app network-level access |
| Public IP + firewall rules | No | Puts the server on the internet, which breaks requirement 2 |

The trade-off: speed and latency depend on the office broadband, and there's no SLA on the internet part of the path.

### Route-based gateway

Route-based is needed for IKEv2, and it leaves room to grow (BGP, active-active, adding point-to-site later). Policy-based is really only there for old devices.

### Gateway SKU: VpnGw1AZ

- The non-AZ SKUs (VpnGw1–5) were retired in September 2026 and can't be created any more, so AZ is the standard now
- VpnGw1AZ is the smallest SKU that supports IKEv2, a custom IPsec policy, BGP and active-active. That's plenty for 20 people
- I ruled out Basic: no custom IPsec policy and no BGP, so the customer would have to rebuild later to grow

### Custom IPsec policy instead of Azure's defaults

By default Azure offers a list of proposals so it can work with lots of devices. I pinned both ends to one strong set instead:

| Phase | Settings |
| --- | --- |
| Phase 1 (IKE) | IKEv2 · AES256 · SHA256 · DH group 14 |
| Phase 2 (IPsec) | AES256 · SHA256 · PFS2048 · 27000 s lifetime · no data-size limit |

That means nothing can drop to weaker crypto, both ends behave predictably, and the settings are written down and auditable.

**In plain English:** phase 1 is the two routers proving who they are and setting up a secure "control channel". Phase 2 uses that channel to build the actual tunnel the data goes through. Every setting has to match on both ends, otherwise you get `NO_PROPOSAL_CHOSEN` and nothing comes up.

### Region: UK South

I wanted North Europe (Dublin) because it's closest. It didn't work out (see [troubleshooting](../08-Troubleshooting/README.md)), so I went with **UK South** in London. That adds roughly 10–20 ms, which makes no difference for an office app. For a customer with strict data-residency rules, I'd confirm the region with them first.

### GatewaySubnet sized /27

32 addresses, which is Microsoft's recommended minimum. That leaves room for active-active and for ExpressRoute alongside the VPN later on, and you can't resize the GatewaySubnet once a gateway is in it.

### Active-standby, no BGP

One office router and one internet line, so active-active and BGP add cost and complexity for no real benefit. If the customer adds a second ISP or a second office, I'd turn both on.

---

## Security

| Control | How |
| --- | --- |
| Encryption in transit | IPsec IKEv2, AES256 / SHA256, DH14, PFS2048 |
| Server not on the internet | The VM has no public IP and is only reachable through the tunnel |
| Private subnet | No default outbound internet access from the workload subnet |
| Locked-down port forwards | The Sky Hub only lets UDP 500/4500 in from the Azure gateway's IP |
| MikroTik firewall | Only accepts IKE/NAT-T/ESP from the Azure gateway |
| VM access | SSH key only (Ed25519), no passwords, Trusted Launch with Secure Boot and vTPM |
| Disk | Encrypted at rest by default (platform-managed key) |
| Secrets | The pre-shared key never goes in the repo, and screenshots are blurred |
| Governance | Every resource tagged `project`, `environment`, `owner` |

**For production I'd add:** the pre-shared key in Key Vault, Azure Bastion for admin access, a subnet NSG allowing only SSH/ICMP from the office range, gateway logs into Log Analytics with an alert on tunnel status, and an Azure Policy that blocks public IPs on the workload subnet.

---

## Cost estimate

Indicative pay-as-you-go figures. Always check the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/).

| Resource | If it ran 24/7 (per month) |
| --- | --- |
| VPN Gateway VpnGw1AZ | ~€130–140 |
| Standard public IP | ~€3–4 |
| VM (D2als_v6) + 30 GB Standard SSD | ~€65–70 (a B-series would be ~€8, see section 5) |
| Data over the VPN | Inbound free, first 100 GB out free |
| **Total** | **~€200 / month** (or about €150 with a B-series VM) |

The gateway is the big one. For the lab I only ran things for one afternoon, see [section 9](../09-Cost-and-Cleanup/README.md).

---

## Order of work

1. Azure VNet with a workload subnet and the GatewaySubnet
2. VPN gateway (start it early, because it takes 30–45 minutes)
3. Local network gateway (my home public IP and LAN range)
4. The connection, with the pre-shared key and custom IPsec policy
5. Test VM with no public IP
6. Sky Hub port forwards, then the MikroTik IPsec config
7. Test, take screenshots, tear down
