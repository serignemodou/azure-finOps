import * as network from "@pulumi/azure-native/network";
import * as pulumi from "@pulumi/pulumi";

import { resourceGroup, env, projectName, tags } from './common';

interface networkConfig {
    vnetAddress: [string],
    snetWebAppInbount: string,
    snetWebAppOutbound: string,
    snetStorage: string
}

const ntwConfig = new pulumi.Config('network').requireObject<networkConfig>('config')

const vnetName = `vnet-${projectName}-${env}`
const virtualNetwork = new network.VirtualNetwork(vnetName, {
    resourceGroupName: resourceGroup.name,
    location: resourceGroup.location,
    virtualNetworkName: vnetName,
    addressSpace: {
        addressPrefixes: ntwConfig.vnetAddress
    },
    tags: tags
})

const snetInboundName = `snet-inbound-${projectName}-${env}`
export const snetInbound = new network.Subnet(snetInboundName, {
    resourceGroupName: resourceGroup.name,
    subnetName: snetInboundName,
    virtualNetworkName: virtualNetwork.name,
    addressPrefix: ntwConfig.snetWebAppInbount,
    privateEndpointNetworkPolicies: network.VirtualNetworkPrivateEndpointNetworkPolicies.Enabled
})

const snetOutboundName = `snet-outbound-${projectName}-${env}`
export const snetOutbound = new network.Subnet(snetOutboundName, {
    resourceGroupName: resourceGroup.name,
    subnetName: snetOutboundName,
    virtualNetworkName: virtualNetwork.name,
    addressPrefix: ntwConfig.snetWebAppOutbound,
    privateEndpointNetworkPolicies: network.VirtualNetworkPrivateEndpointNetworkPolicies.Enabled,
    delegations: [
        {
            name: 'VnetIntegration',
            serviceName: 'Microsoft.Web/serverFrams'
        }
    ]
})

const snetStorageName = `snet-storage-${projectName}-${env}`
export const snetStorage = new network.Subnet(snetStorageName, {
    resourceGroupName: resourceGroup.name,
    subnetName: snetStorageName,
    virtualNetworkName: virtualNetwork.name,
    addressPrefix: ntwConfig.snetStorage,
    privateEndpointNetworkPolicies: network.VirtualNetworkPrivateEndpointNetworkPolicies.Enabled
})