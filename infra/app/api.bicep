param name string
@description('Primary location for all resources & Flex Consumption Function App')
param location string = resourceGroup().location
param tags object = {}
param applicationInsightsName string = ''
param appServicePlanId string
param appSettings object = {}
param runtimeName string
param runtimeVersion string
param serviceName string = 'api'
param storageAccountName string
param deploymentStorageContainerName string
param instanceMemoryMB int = 2048
param maximumInstanceCount int = 100
param identityId string = ''
param identityClientId string = ''
param enableBlob bool = true
param enableQueue bool = false
param enableTable bool = false
param enableFile bool = false
param dtsURL string = ''
param taskHubName string = ''

@description('OTLP endpoint used by the PowerShell worker (OpenTelemetry).')
param otelExporterOtlpEndpoint string = ''

@description('OTLP headers used by the PowerShell worker (OpenTelemetry). Treat as secret at deploy time.')
@secure()
param otelExporterOtlpHeaders string = ''

@allowed(['SystemAssigned', 'UserAssigned'])
param identityType string = 'UserAssigned'

var applicationInsightsIdentity = 'ClientId=${identityClientId};Authorization=AAD'
var kind = 'functionapp,linux'

// Core app settings always required by the Functions host / AI integration
var baseAppSettings = {
  AzureWebJobsStorage__credential: 'managedidentity'
  AzureWebJobsStorage__clientId: identityClientId
  APPLICATIONINSIGHTS_AUTHENTICATION_STRING: applicationInsightsIdentity
  APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
}

// Settings required by the PowerShell OpenTelemetry sample. Preserved from the pre-DTS app.
var otelSettings = {
  OTEL_FUNCTIONS_WORKER_ENABLED: 'true'
  ExternalDurablePowerShellSDK: 'true'
  OTEL_EXPORTER_OTLP_ENDPOINT: otelExporterOtlpEndpoint
  OTEL_EXPORTER_OTLP_HEADERS: otelExporterOtlpHeaders
}

// Durable Task Scheduler settings (only when deployed to Azure)
var dtsSettings = !empty(dtsURL) ? {
  DURABLE_TASK_SCHEDULER_CONNECTION_STRING: 'Endpoint=${dtsURL};Authentication=ManagedIdentity;ClientID=${identityClientId}'
  TASKHUB_NAME: taskHubName
} : {}

// Storage endpoint settings — DTS only requires blob (for AzureWebJobsStorage/deployment)
var blobSettings = enableBlob ? { AzureWebJobsStorage__blobServiceUri: stg.properties.primaryEndpoints.blob } : {}
var queueSettings = enableQueue ? { AzureWebJobsStorage__queueServiceUri: stg.properties.primaryEndpoints.queue } : {}
var tableSettings = enableTable ? { AzureWebJobsStorage__tableServiceUri: stg.properties.primaryEndpoints.table } : {}
var fileSettings = enableFile ? { AzureWebJobsStorage__fileServiceUri: stg.properties.primaryEndpoints.file } : {}

var allAppSettings = union(
  appSettings,
  blobSettings,
  queueSettings,
  tableSettings,
  fileSettings,
  baseAppSettings,
  otelSettings,
  dtsSettings
)

resource stg 'Microsoft.Storage/storageAccounts@2022-09-01' existing = {
  name: storageAccountName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = if (!empty(applicationInsightsName)) {
  name: applicationInsightsName
}

module api 'br/public:avm/res/web/site:0.15.1' = {
  name: '${serviceName}-flex-consumption'
  params: {
    kind: kind
    name: name
    location: location
    tags: union(tags, { 'azd-service-name': serviceName })
    serverFarmResourceId: appServicePlanId
    managedIdentities: {
      systemAssigned: identityType == 'SystemAssigned'
      userAssignedResourceIds: [
        '${identityId}'
      ]
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${stg.properties.primaryEndpoints.blob}${deploymentStorageContainerName}'
          authentication: {
            type: identityType == 'SystemAssigned' ? 'SystemAssignedIdentity' : 'UserAssignedIdentity'
            userAssignedIdentityResourceId: identityType == 'UserAssigned' ? identityId : ''
          }
        }
      }
      scaleAndConcurrency: {
        instanceMemoryMB: instanceMemoryMB
        maximumInstanceCount: maximumInstanceCount
      }
      runtime: {
        name: runtimeName
        version: runtimeVersion
      }
    }
    siteConfig: {
      alwaysOn: false
    }
    appSettingsKeyValuePairs: allAppSettings
  }
}

output SERVICE_API_NAME string = api.outputs.name
output SERVICE_API_IDENTITY_PRINCIPAL_ID string = identityType == 'SystemAssigned' ? api.outputs.?systemAssignedMIPrincipalId ?? '' : ''
