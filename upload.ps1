param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,

    [string]$ContainerName = '$web',

    [string]$SourceFolder = (Join-Path $PSScriptRoot 'docs'),

    [string]$IndexDocument = 'index.json',

    [string]$ErrorDocument = '404.json'
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) is required to upload the static registry files.'
}

$resolvedSource = (Resolve-Path -Path $SourceFolder).Path

Write-Host "Enabling static website on storage account '$StorageAccountName'..."
az storage blob service-properties update `
    --account-name $StorageAccountName `
    --auth-mode login `
    --static-website true `
    --index-document $IndexDocument `
    --404-document $ErrorDocument `
    --only-show-errors | Out-Null

Write-Host "Uploading '$resolvedSource' to blob container '$ContainerName'..."
az storage blob upload-batch `
    --source $resolvedSource `
    --destination $ContainerName `
    --account-name $StorageAccountName `
    --auth-mode login `
    --overwrite true `
    --only-show-errors | Out-Null

$webEndpoint = az storage account show `
    --name $StorageAccountName `
    --resource-group $ResourceGroupName `
    --query 'primaryEndpoints.web' `
    --output tsv

if ([string]::IsNullOrWhiteSpace($webEndpoint)) {
    throw 'Could not determine the static website endpoint for the storage account.'
}

Write-Host "Static website endpoint: $webEndpoint"
Write-Host "Registry index: $($webEndpoint.TrimEnd('/'))/v0.1/servers/index.json"
