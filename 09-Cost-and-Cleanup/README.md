# 09 — Cost and Cleanup

The VPN gateway bills by the hour whether you use it or not, so the plan was always: build it, test it, screenshot it, delete it, all in one go.

---

## What it cost

| Resource | Roughly how long it ran | Approx. rate |
| --- | --- | --- |
| VPN Gateway VpnGw1AZ | ~7 hours | ~€0.18 / hour |
| Public IP | ~7 hours | about €0.005 / hour |
| VM D2als_v6 | ~2 hours | ~€0.09 / hour |
| Local network gateway, VNet, connection | | Free |

**Lab total: about €1.50.** The same setup left running 24/7 would be about €200 a month, nearly all of it the gateway, so tearing down straight away really matters.

Because everything was tagged `project = azure-s2s-vpn-lab`, Cost Management can show the exact cost of just this lab.

**Cost guardrails I used:**
- A budget on the subscription with alerts at 50%, 80% and 100%
- Auto-shutdown on the VM at 23:30
- One resource group for everything, so a single delete removes the lot

---

## Cleanup

**Azure:** deleted the whole `tim-the-tech-guy` resource group, which removed the gateway, public IP, connection, local network gateway, VM, disk, NIC, NSG and VNet in one go.

**MikroTik:** removed the tunnel config (the same commands are in [`mikrotik/teardown.rsc`](../mikrotik/teardown.rsc)) and deleted the uploaded `.rsc` file from the router, because it had the pre-shared key in it.

**Sky Hub:** deleted the two inbound rules for UDP 500 and 4500. There's no point leaving ports forwarded to a tunnel that doesn't exist any more.

**My Mac:** deleted the filled-in `.rsc` file and the VM's SSH key.

---

## What I'd do next

- [ ] Deploy the same design from the Bicep in [`infra/`](../infra/) and compare it with the portal build
- [ ] Replace the default NSG with a subnet NSG that only allows SSH/ICMP from `192.168.88.0/24`
- [ ] Put the pre-shared key in Key Vault
- [ ] Add Azure Bastion for admin access that doesn't depend on the tunnel
- [ ] Point-to-site VPN with Entra ID sign-in for remote staff
- [ ] Active-active gateway + BGP, for when there's a second ISP
- [ ] Hub-and-spoke with Azure Firewall as the network grows
- [ ] Deploy from GitHub Actions using OIDC (no stored credentials)
