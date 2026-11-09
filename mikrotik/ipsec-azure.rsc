# =============================================================================
# MikroTik RouterOS v7 - IPsec IKEv2 site-to-site tunnel to Azure VPN Gateway
#
# Before importing, replace:
#   AZURE_GW_IP   -> vpnGatewayPublicIp output from the Bicep deployment
#   PSK_HERE      -> contents of .psk (NEVER commit the real value)
#   HOME_PUBLIC_IP -> your ISP public IP (same as the Local Network Gateway)
#
# Double NAT (ISP router in front of the MikroTik): forward UDP 500 and
# UDP 4500 on the ISP router to the MikroTik's WAN IP, ideally only from
# AZURE_GW_IP. NAT-T wraps ESP inside UDP 4500.
#
# Local LAN : 192.168.88.0/24   (MikroTik default bridge network)
# Azure VNet: 10.10.0.0/16
#
# Crypto must match the ipsecPolicies block in infra/main.bicep:
#   IKE  : AES256 / SHA256 / DH14 (modp2048), SA lifetime 8h (Azure IKEv2 default 28800s)
#   ESP  : AES256 / SHA256 / PFS 2048,        SA lifetime 27000s (7h30m)
#
# Import with: /import file-name=ipsec-azure.rsc verbose=yes
# =============================================================================

# --- Phase 1 (IKE) -----------------------------------------------------------
/ip ipsec profile
add name=azure-ike hash-algorithm=sha256 enc-algorithm=aes-256 \
    dh-group=modp2048 lifetime=8h nat-traversal=yes dpd-interval=30s \
    dpd-maximum-failures=5

/ip ipsec peer
add name=azure address=AZURE_GW_IP/32 exchange-mode=ike2 profile=azure-ike \
    comment="Azure VPN Gateway"

/ip ipsec identity
# my-id: behind double NAT (ISP router -> MikroTik), the MikroTik would otherwise
# identify itself by its private WAN IP. Azure expects the public IP configured
# in the Local Network Gateway, so we set it explicitly.
add peer=azure auth-method=pre-shared-key secret="PSK_HERE" \
    my-id=address:HOME_PUBLIC_IP

# --- Phase 2 (ESP) -----------------------------------------------------------
/ip ipsec proposal
add name=azure-esp auth-algorithms=sha256 enc-algorithms=aes-256-cbc \
    pfs-group=modp2048 lifetime=7h30m

/ip ipsec policy
add peer=azure tunnel=yes src-address=192.168.88.0/24 dst-address=10.10.0.0/16 \
    action=encrypt level=require proposal=azure-esp comment="LAN <-> Azure VNet"

# --- NAT bypass --------------------------------------------------------------
# Without this, masquerade rewrites the source address BEFORE the IPsec policy
# is matched, so traffic leaves unencrypted and never reaches Azure.
/ip firewall nat
add chain=srcnat action=accept src-address=192.168.88.0/24 \
    dst-address=10.10.0.0/16 place-before=0 comment="No NAT to Azure (IPsec)"

# --- Firewall: allow tunnel traffic and keep it out of FastTrack ------------
/ip firewall filter
add chain=input action=accept protocol=udp port=500,4500 \
    src-address=AZURE_GW_IP place-before=0 comment="IKE/NAT-T from Azure"
add chain=input action=accept protocol=ipsec-esp src-address=AZURE_GW_IP \
    place-before=0 comment="ESP from Azure"
add chain=forward action=accept ipsec-policy=in,ipsec place-before=0 \
    comment="Accept decrypted IPsec traffic"
add chain=forward action=accept ipsec-policy=out,ipsec place-before=0 \
    comment="Accept traffic to be encrypted"

# --- MSS clamping ------------------------------------------------------------
# Microsoft recommends clamping TCP MSS to 1350 on the on-prem device to avoid
# fragmentation inside the tunnel (symptom: ping works, SSH/HTTPS hangs).
/ip firewall mangle
add chain=forward action=change-mss new-mss=1350 passthrough=yes protocol=tcp \
    tcp-flags=syn src-address=192.168.88.0/24 dst-address=10.10.0.0/16 \
    tcp-mss=1351-65535 comment="Clamp MSS to Azure"
add chain=forward action=change-mss new-mss=1350 passthrough=yes protocol=tcp \
    tcp-flags=syn src-address=10.10.0.0/16 dst-address=192.168.88.0/24 \
    tcp-mss=1351-65535 comment="Clamp MSS from Azure"

# --- Verify ------------------------------------------------------------------
# /ip ipsec active-peers print
# /ip ipsec installed-sa print
# /log print where topics~"ipsec"
