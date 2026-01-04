@description('The name of the Storage Account. Must be globally unique and max 24 chars.')
param storageAccountName string = 'checklist'

@description('The location for all resources.')
param location string = resourceGroup().location

@description('The start time for the SAS policy.')
param policyStartTime string = utcNow('yyyy-MM-ddTHH:mm:ssZ')

@description('The expiry time for the SAS policy.')
param policyExpiryTime string = dateTimeAdd(utcNow(), 'P1Y', 'yyyy-MM-ddTHH:mm:ssZ')

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: false
    accessTier: 'Hot'
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// Blob Service (existing reference; no retention policy)
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' existing = {
  parent: storageAccount
  name: 'default'
}

// Table Service (for CORS)
resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: [
        {
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'HEAD', 'MERGE', 'POST', 'OPTIONS', 'PUT', 'DELETE']
          maxAgeInSeconds: 200
          exposedHeaders: ['*']
          allowedHeaders: ['*']
        }
      ]
    }
  }
}

// Storage Table
resource storageTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-01-01' = {
  parent: tableService
  name: storageAccount.name
}

// $web Container
resource webContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: '$web'
  properties: {
    publicAccess: 'None'
  }
}

// Managed Identity for Deployment Script
resource scriptIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${storageAccountName}-identity'
  location: location
}

// Role Assignments
var roleStorageAccountContributor = '17d1049b-9a84-46fb-8f53-869881c3d3ab'
var roleStorageTableDataContributor = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
var roleStorageBlobDataContributor = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

resource raContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, scriptIdentity.id, 'StorageAccountContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleStorageAccountContributor)
    principalId: scriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource raTableData 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, scriptIdentity.id, 'StorageTableDataContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleStorageTableDataContributor)
    principalId: scriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource raBlobData 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, scriptIdentity.id, 'StorageBlobDataContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleStorageBlobDataContributor)
    principalId: scriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Deployment Script
resource configureStorage 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'configure-storage-script'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${scriptIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.60.0'
    retentionInterval: 'PT1H'
    cleanupPreference: 'OnSuccess'
    environmentVariables: [
      { name: 'STORAGE_ACCOUNT_NAME', value: storageAccount.name }
      { name: 'RESOURCE_GROUP_NAME', value: resourceGroup().name }
      { name: 'TABLE_NAME', value: storageAccount.name } 
      { name: 'POLICY_START', value: policyStartTime }
      { name: 'POLICY_EXPIRY', value: policyExpiryTime }
      { name: 'INDEX_HTML_CONTENT', value: loadFileAsBase64('index.html') }
    ]
    scriptContent: '''
      set -e

      echo "Retrieving Storage Account Key..."
      ACCOUNT_KEY=$(az storage account keys list --account-name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "[0].value" -o tsv)

      export AZURE_STORAGE_ACCOUNT=$STORAGE_ACCOUNT_NAME
      export AZURE_STORAGE_KEY=$ACCOUNT_KEY

      echo "Enabling Static Website..."
      az storage blob service-properties update --account-name "$STORAGE_ACCOUNT_NAME" --static-website --index-document index.html

      echo "Configuring Table Access Policies..."

      # Function to create or update policy
      set_policy() {
        local name=$1
        local perms=$2
        az storage table policy create \
          --account-name "$STORAGE_ACCOUNT_NAME" \
          --name "$name" \
          --table-name "$TABLE_NAME" \
          --permissions "$perms" \
          --start "$POLICY_START" \
          --expiry "$POLICY_EXPIRY" \
          --output none 2>/dev/null || \
        az storage table policy update \
          --account-name "$STORAGE_ACCOUNT_NAME" \
          --name "$name" \
          --table-name "$TABLE_NAME" \
          --permissions "$perms" \
          --start "$POLICY_START" \
          --expiry "$POLICY_EXPIRY"
      }

      set_policy "webfulledit" "raud"
      set_policy "webqueryupdate" "ru"

      echo "Uploading index.html..."
      echo "$INDEX_HTML_CONTENT" | base64 -d > index.html
      az storage blob upload --account-name "$STORAGE_ACCOUNT_NAME" --container-name '$web' --name index.html --file index.html --content-type "text/html" --overwrite
    '''
  }
  dependsOn: [
    webContainer
    tableService
    storageTable
    raContributor
    raTableData
    raBlobData
  ]
}

output staticWebsiteEndpoint string = storageAccount.properties.primaryEndpoints.web
