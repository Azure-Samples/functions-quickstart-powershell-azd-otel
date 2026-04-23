targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
@allowed([
  'australiaeast'
  'centralus'
  'eastasia'
  'eastus2'
  'northcentralus'
  'northeurope'
  'southeastasia'
  'swedencentral'
  'uksouth'
  'westus2'
])
@metadata({
  azd: {
    type: 'location'
  }
})
param location string = 'northcentralus'

param apiServiceName string = ''
param apiUserAssignedIdentityName string = ''
param applicationInsightsName string = ''
param appServicePlanName string = ''
param logAnalyticsName string = ''
param resourceGroupName string = ''
param storageAccountName string = ''
param dtsName string = ''
param taskHubName string = ''
param dtsLocation string = location
param dtsSkuName string = 'Consumption'
param dtsCapacity int = 1

@description('OTLP endpoint used by the PowerShell worker for OpenTelemetry export.')
param otelExporterOtlpEndpoint string = ''

@description('OTLP headers used by the PowerShell worker for OpenTelemetry export.')
@secure()
param otelExporterOtlpHeaders string = ''

@description('Id of the user identity to be used for testing and debugging. This is not required in production. Leave empty if not needed.')
param principalId string = deployer().objectId

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }
var functionAppName = !empty(apiServiceName) ? apiServiceName : '${abbrs.webSitesFunctions}api-${resourceToken}'
var dtsResourceName = !empty(dtsName) ? dtsName : '${abbrs.durableTaskSchedulers}${resourceToken}'
var taskHubResourceName = !empty(taskHubName) ? taskHubName : '${abbrs.durableTaskHubs}${resourceToken}'
var deploymentStorageContainerName = 'app-package-${take(functionAppName, 32)}-${take(toLower(uniqueString(functionAppName, resourceToken)), 7)}'

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

module apiUserAssignedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'apiUserAssignedIdentity'
  scope: rg
  params: {
    location: location
    tags: tags
    name: !empty(apiUserAssignedIdentityName) ? apiUserAssignedIdentityName : '${abbrs.managedIdentityUserAssignedIdentities}api-${resourceToken}'
  }
}

module appServicePlan 'br/public:avm/res/web/serverfarm:0.1.1' = {
  name: 'appserviceplan'
  scope: rg
  params: {
    name: !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webServerFarms}${resourceToken}'
    sku: {
      name: 'FC1'
      tier: 'FlexConsumption'
    }
    reserved: true
    location: location
    tags: tags
  }
}

module api './app/api.bicep' = {
  name: 'api'
  scope: rg
  params: {
    name: functionAppName
    location: location
    tags: tags
    applicationInsightsName: monitoring.outputs.name
    appServicePlanId: appServicePlan.outputs.resourceId
    runtimeName: 'powershell'
    runtimeVersion: '7.4'
    storageAccountName: storage.outputs.name
    enableBlob: storageEndpointConfig.enableBlob
    enableQueue: storageEndpointConfig.enableQueue
    enableTable: storageEndpointConfig.enableTable
    deploymentStorageContainerName: deploymentStorageContainerName
    identityId: apiUserAssignedIdentity.outputs.resourceId
    identityClientId: apiUserAssignedIdentity.outputs.clientId
    appSettings: {}
    dtsURL: dts.outputs.dts_URL
    taskHubName: dts.outputs.TASKHUB_NAME
    otelExporterOtlpEndpoint: otelExporterOtlpEndpoint
    otelExporterOtlpHeaders: otelExporterOtlpHeaders
  }
}

// Backing storage for Azure Functions (deployment package + AzureWebJobsStorage blob).
module storage 'br/public:avm/res/storage/storage-account:0.8.3' = {
  name: 'storage'
  scope: rg
  params: {
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    dnsEndpointType: 'Standard'
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    blobServices: {
      containers: [{ name: deploymentStorageContainerName }]
    }
    minimumTlsVersion: 'TLS1_2'
    location: location
    tags: tags
  }
}

var storageEndpointConfig = {
  enableBlob: true
  enableQueue: true   // Required for AzureWebJobsStorage host operations and non-Durable triggers/bindings
  enableTable: true   // Required for AzureWebJobsStorage host operations and non-Durable triggers/bindings
  enableFiles: false
  allowUserIdentityPrincipal: true
}

module rbac 'app/rbac.bicep' = {
  name: 'rbacAssignments'
  scope: rg
  params: {
    storageAccountName: storage.outputs.name
    appInsightsName: monitoring.outputs.name
    managedIdentityPrincipalId: apiUserAssignedIdentity.outputs.principalId
    userIdentityPrincipalId: principalId
    enableBlob: storageEndpointConfig.enableBlob
    enableQueue: storageEndpointConfig.enableQueue
    enableTable: storageEndpointConfig.enableTable
    allowUserIdentityPrincipal: storageEndpointConfig.allowUserIdentityPrincipal
  }
}

module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.11.1' = {
  name: '${uniqueString(deployment().name, location)}-loganalytics'
  scope: rg
  params: {
    name: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    location: location
    tags: tags
    dataRetention: 30
  }
}

module monitoring 'br/public:avm/res/insights/component:0.6.0' = {
  name: '${uniqueString(deployment().name, location)}-appinsights'
  scope: rg
  params: {
    name: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}${resourceToken}'
    location: location
    tags: tags
    workspaceResourceId: logAnalytics.outputs.resourceId
    disableLocalAuth: true
  }
}

module dts './app/dts.bicep' = {
  scope: rg
  name: 'dtsResource'
  params: {
    name: dtsResourceName
    taskhubname: taskHubResourceName
    location: dtsLocation
    tags: tags
    ipAllowlist: [
      '0.0.0.0/0'
    ]
    skuName: dtsSkuName
    skuCapacity: dtsCapacity
  }
}

var dtsRoleDefinitionId = '0ad04412-c4d5-4796-b79c-f76d14c8d402'

module dtsRoleAssignment 'app/dts-Access.bicep' = {
  name: 'dtsRoleAssignment'
  scope: rg
  params: {
    roleDefinitionID: dtsRoleDefinitionId
    principalID: apiUserAssignedIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
    dtsName: dts.outputs.dts_NAME
  }
}

module dtsDashboardRoleAssignment 'app/dts-Access.bicep' = {
  name: 'dtsDashboardRoleAssignment'
  scope: rg
  params: {
    roleDefinitionID: dtsRoleDefinitionId
    principalID: principalId
    principalType: 'User'
    dtsName: dts.outputs.dts_NAME
  }
}

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output SERVICE_API_NAME string = api.outputs.SERVICE_API_NAME
output AZURE_FUNCTION_NAME string = api.outputs.SERVICE_API_NAME
