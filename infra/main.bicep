// =============================================================================
// Azure Site-to-Site VPN Lab
// Hybrid connectivity between an on-premises MikroTik router and an Azure VNet.
//
// Deploys:
//   - Virtual network with GatewaySubnet + workload subnet
//   - NSG on the workload subnet (only on-prem traffic allowed in)
//   - Zone-redundant Standard public IP for the VPN gateway
//   - Route-based VPN gateway (VpnGw1AZ)
//   - Local network gateway (represents the on-prem site)
//   - IPsec/IKEv2 connection with a custom (non-default) IPsec policy
//   - Small Linux test VM with NO public IP
// =============================================================================

targetScope = 'resourceGroup'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Short prefix used in resource names.')
@maxLength(10)
param prefix string = 's2slab'

@description('Address space for the Azure VNet.')
param vnetAddressPrefix string = '10.10.0.0/16'

@description('Workload subnet (where the test VM lives).')
param workloadSubnetPrefix string = '10.10.1.0/24'

@description('GatewaySubnet. /27 is the Microsoft-recommended minimum.')
param gatewaySubnetPrefix string = '10.10.2.0/27'

@description('Public IP address of the on-premises VPN device (home router WAN IP).')
param onPremPublicIp string

@description('On-premises LAN address space(s) reachable through the tunnel.')
param onPremAddressPrefixes array = [
  '192.168.88.0/24'
]

@description('IPsec pre-shared key. Never commit this - pass it at deploy time.')
@secure()
@minLength(20)
param sharedKey string

@description('VPN gateway SKU. Non-AZ SKUs (VpnGw1-5) can no longer be created.')
@allowed([
  'VpnGw1AZ'
  'VpnGw2AZ'
])
param gatewaySku string = 'VpnGw1AZ'

@description('Admin username for the test VM.')
param adminUsername string = 'azureuser'

@description('SSH public key for the test VM (password auth is disabled).')
param sshPublicKey string

@description('Test VM size.')
param vmSize string = 'Standard_D2als_v6' // B-series is cheaper if your subscription has quota for it

@description('Tags applied to every resource - used for cost tracking and cleanup.')
param tags object = {
  project: 'azure-s2s-vpn-lab'
  environment: 'lab'
  owner: 'tim-tapsell'
}

// -----------------------------------------------------------------------------
// Names
// -----------------------------------------------------------------------------
var vnetName = '${prefix}-vnet'
var nsgName = '${prefix}-workload-nsg'
var gwPipName = '${prefix}-vpngw-pip'
var gwName = '${prefix}-vpngw'
var lngName = '${prefix}-lng-home'
var connName = '${prefix}-conn-home'
var vmName = '${prefix}-vm01'
var nicName = '${vmName}-nic'

// -----------------------------------------------------------------------------
// Network security group - workload subnet
// Only the on-prem LAN may reach the VM (SSH + ICMP). Everything else inbound
// is explicitly denied, overriding the default AllowVnetInBound rule.
// -----------------------------------------------------------------------------
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-From-OnPrem'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefixes: onPremAddressPrefixes
          sourcePortRange: '*'
          destinationAddressPrefix: workloadSubnetPrefix
          destinationPortRange: '22'
        }
      }
      {
        name: 'Allow-ICMP-From-OnPrem'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Icmp'
          sourceAddressPrefixes: onPremAddressPrefixes
          sourcePortRange: '*'
          destinationAddressPrefix: workloadSubnetPrefix
          destinationPortRange: '*'
        }
      }
      {
        name: 'Deny-All-Other-Inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Virtual network
// GatewaySubnet must be named exactly "GatewaySubnet" and must NOT have an NSG.
// -----------------------------------------------------------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: gatewaySubnetPrefix
        }
      }
      {
        name: 'snet-workload'
        properties: {
          addressPrefix: workloadSubnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// VPN gateway public IP - Standard, static, zone-redundant (required by AZ SKUs)
// -----------------------------------------------------------------------------
resource gwPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: gwPipName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// -----------------------------------------------------------------------------
// VPN gateway - route-based, single instance (active-standby)
// Takes ~30-45 minutes to deploy.
// -----------------------------------------------------------------------------
resource vpnGw 'Microsoft.Network/virtualNetworkGateways@2024-05-01' = {
  name: gwName
  location: location
  tags: tags
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    vpnGatewayGeneration: 'Generation1'
    sku: {
      name: gatewaySku
      tier: gatewaySku
    }
    activeActive: false
    enableBgp: false
    ipConfigurations: [
      {
        name: 'gwipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${vnet.id}/subnets/GatewaySubnet'
          }
          publicIPAddress: {
            id: gwPip.id
          }
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Local network gateway - Azure's representation of the home site
// -----------------------------------------------------------------------------
resource lng 'Microsoft.Network/localNetworkGateways@2024-05-01' = {
  name: lngName
  location: location
  tags: tags
  properties: {
    gatewayIpAddress: onPremPublicIp
    localNetworkAddressSpace: {
      addressPrefixes: onPremAddressPrefixes
    }
  }
}

// -----------------------------------------------------------------------------
// Site-to-site connection
// Custom IPsec policy pins both ends to the same strong crypto instead of
// relying on Azure's default proposal list. Must match mikrotik/ipsec-azure.rsc.
// -----------------------------------------------------------------------------
resource conn 'Microsoft.Network/connections@2024-05-01' = {
  name: connName
  location: location
  tags: tags
  properties: {
    connectionType: 'IPsec'
    connectionProtocol: 'IKEv2'
    virtualNetworkGateway1: {
      id: vpnGw.id
      properties: {}
    }
    localNetworkGateway2: {
      id: lng.id
      properties: {}
    }
    sharedKey: sharedKey
    enableBgp: false
    usePolicyBasedTrafficSelectors: false
    ipsecPolicies: [
      {
        ikeEncryption: 'AES256'
        ikeIntegrity: 'SHA256'
        dhGroup: 'DHGroup14'
        ipsecEncryption: 'AES256'
        ipsecIntegrity: 'SHA256'
        pfsGroup: 'PFS2048'
        saLifeTimeSeconds: 27000
        saDataSizeKilobytes: 0 // 0 = no data-based rekey; time-based only, matching MikroTik
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Test VM - private IP only, SSH key auth only
// -----------------------------------------------------------------------------
resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${vnet.id}/subnets/snet-workload'
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        deleteOption: 'Delete'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Outputs - what you need to configure the MikroTik and test the tunnel
// -----------------------------------------------------------------------------
output vpnGatewayPublicIp string = gwPip.properties.ipAddress
output testVmPrivateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output connectionName string = conn.name
output azureAddressSpace string = vnetAddressPrefix
