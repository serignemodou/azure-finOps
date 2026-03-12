import * as monitor from "@pulumi/azure-native/monitor"
import * as insights from "@pulumi/azure-native/applicationinsights"


import {env, projectName, resourceGroup} from './common';
import {law} from './logsAnalytics'

const appInsightName = `appi-${projectName}-${env}`
export const appInsight = new insights.Component(appInsightName, {
    resourceName: appInsightName,
    resourceGroupName: resourceGroup.name,
    location: resourceGroup.location,
    applicationType: insights.ApplicationType.Other,
    kind: 'java',
    workspaceResourceId: law.id,
    ingestionMode: insights.IngestionMode.LogAnalytics,
    requestSource: insights.RequestSource.Rest
})