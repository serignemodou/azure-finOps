import * as web from "@pulumi/azure-native/web"
import {input} from "@pulumi/azure-native/types"
import * as network from "@pulumi/azure-native/network";
import * as identity from "@pulumi/azure-native/managedidentity";
import * as authorization from "@pulumi/azure-native/authorization";

import {env, resourceGroup, projectName, tags} from "./common"
import {storageAccount} from "./storage"
import {snetInbound, snetOutbound} from "./network"
import {appInsight} from "./appInsights"


const uaiFunctionAppName = `uai-func-${projectName}-${env}`
export const uaiFunctionApp = new identity.UserAssignedIdentity(uaiFunctionAppName, {
    resourceGroupName: resourceGroup.name,
    location: resourceGroup.location,
    resourceName: uaiFunctionAppName
})

export const functionName = `func-appgw-${env}`

export const siteConfig : input.web.SiteConfigArgs = {
    vnetRouteAllEnabled: true,
    linuxFxVersion: "PowerShell|7.2",
    publicNetworkAccess: 'Disabled',
    appSettings: [
        /** Begin runtime configuration */
        {
            name: 'FUNCTIONS_WORKER_RUNTIME',
            value: 'powershell'
        },
        {
            name: 'FUNCTION_EXTENSION_VERSION',
            value: '~4'
        },
        {
            name: 'FUNCTIONS_WORKER_PROCESS_COUNT',
            value: '4'
        },
        {
            name: 'WEBSITE_RUN_FROM_PACKAGE',
            value: '1'
        },
        /** Begin: Three params to establish FunctionApp connexion to storage (blob) with user managed identity */
        {
            name: 'AzureWebJobsStorage__accountName',
            value: storageAccount.name
        },
        {
            name: 'APPINSIGTHS_INSTRUMENTATIONKEY',
            value: appInsight.instrumentationKey
        },
        {
            name: 'APPLICATIONINSIGHTS_CONNECTION_STRING',
            value: appInsight.connectionString,
        },
        {
            name: 'ApplicationInsightsAgent_EXTENSION_VERSION',
            value: '~3'
        },
        /** App insights monitoring configuration */
        {
            name: 'AZURE_CLIENT_ID',
            value: uaiFunctionApp.clientId
        },
        {
            name: 'PSWorkerInProcConcurrencyUpperBound',
            value: '4'
        }
    ],
    //https://learn.microsoft.com/en-us/azure/azure-functions/functions-app-settings
    minTlsVersion: web.SupportedTlsVersions.SupportedTlsVersions_1_2
}

export const functionApp = new web.WebApp(functionName, {
    resourceGroupName: resourceGroup.name,
    location:resourceGroup.location,
    name: functionName,
    identity: {
        type: web.ManagedServiceIdentityType.UserAssigned,
        userAssignedIdentities: [uaiFunctionApp.id]
    },
    kind: 'functionapp,linux',
    httpsOnly: true,
    reserved: true,
    tags,
    siteConfig,
    publicNetworkAccess: 'Disabled',
    virtualNetworkSubnetId: snetOutbound.id, //Outbound trafic
})


new network.PrivateEndpoint(`pe-${functionName}`, {
    resourceGroupName: resourceGroup.name,
    location: resourceGroup.location,
    privateEndpointName: `pe-${functionName}`,
    subnet: {
        id: snetInbound.id  
    },
    id: functionApp.id,
})

new authorization.RoleAssignment(`blob-data-contributor-rule`, {
    principalId: uaiFunctionApp.principalId,
    principalType: authorization.PrincipalType.ServicePrincipal,
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe', // Blob data contributor rule
    scope: storageAccount.id,
})