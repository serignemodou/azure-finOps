import * as storage from "@pulumi/azure-native/storage"
import * as network from "@pulumi/azure-native/network";

import {env, resourceGroup, projectName, tags} from "./common"
import {snetStorage} from "./network"

const storageAccountName = `safuncappgw${env}`

export const storageAccount = new storage.StorageAccount(storageAccountName, {
    accountName: storageAccountName,
    resourceGroupName: resourceGroup.name,
    location: resourceGroup.location,
    sku: {
        name: storage.SkuName.Standard_ZRS,
    },
    kind: storage.Kind.StorageV2,
    allowBlobPublicAccess: false,
    enableHttpsTrafficOnly: true,
    minimumTlsVersion: storage.MinimumTlsVersion.TLS1_2,
    networkRuleSet: {
        defaultAction: 'Deny',
        bypass: 'Logging, Metrics, AzureServices',
        ipRules: [{
            iPAddressOrRange: "0.0.0.0/0",
            action: storage.Action.Allow,
        }]
    },
    tags: tags,
})

new storage.BlobServiceProperties(`blobServiceProperties-${env}`, {
    accountName: storageAccount.name,
    resourceGroupName: resourceGroup.name,
    blobServicesName: 'default',
    defaultServiceVersion: '2017-07-29',
    deleteRetentionPolicy: {
        enabled: true,
        days: 7
    }
})

const peName = `pe-afunc-${projectName}-${env}`
new network.PrivateEndpoint(peName, {
    resourceGroupName: resourceGroup.name,
    location: resourceGroup.location,
    subnet: {
        id: snetStorage.id,
    },
    privateLinkServiceConnections: [{
        name: peName,
        privateLinkServiceId: storageAccount.id,
    }],
    tags: tags
})