import * as resources from "@pulumi/azure-native/resources"
import * as pulumi from '@pulumi/pulumi';

export const env = pulumi.getStack()
export const projectName = pulumi.getProject()
export const projectConfig = new pulumi.Config('project')

export const azureNativeConfig = new pulumi.Config('azure-native')
export const subscriptionId = azureNativeConfig.require('subscriptionId')

export const tags  = {
    'project:name': pulumi.getProject(),
    'project:url': projectConfig.require('url'),
    'pulumi:stack': pulumi.getStack(),
}

const resourceGroupName = `rg-${projectName}-${env}`
export const resourceGroup = new resources.ResourceGroup(resourceGroupName, {
    resourceGroupName: resourceGroupName,
    tags: tags
})