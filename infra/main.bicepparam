using './main.bicep'

// Non-secret values - safe to commit. Edit to suit your network.
param location = 'uksouth'
param prefix = 's2slab'
param vnetAddressPrefix = '10.10.0.0/16'
param workloadSubnetPrefix = '10.10.1.0/24'
param gatewaySubnetPrefix = '10.10.2.0/27'
param onPremAddressPrefixes = [
  '192.168.88.0/24'
]
param gatewaySku = 'VpnGw1AZ'
param adminUsername = 'azureuser'

// Secrets and environment-specific values are read from environment variables
// at deploy time so they never land in git. See scripts/deploy.sh.
param onPremPublicIp = readEnvironmentVariable('ONPREM_PUBLIC_IP')
param sharedKey = readEnvironmentVariable('VPN_PSK')
param sshPublicKey = readEnvironmentVariable('SSH_PUBLIC_KEY')
