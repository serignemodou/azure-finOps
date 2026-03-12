import * as authorization from "@pulumi/azure-native/authorization";

import {storageAccount} from "./storage"
import {uaiFunctionApp} from "./function"

new authorization.RoleAssignment('ra-allow-faas-to-join-storageAccount', {
    principalId: uaiFunctionApp.principalId,
    principalType: authorization.PrincipalType.ServicePrincipal,
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/b7e6dc6d-f1e8-4753-8033-0f276bb0955b',
    scope: storageAccount.id,
})