param(
    [string]$RegistryRoot = 'http://localhost:8080',
    [switch]$Compact,
    [int]$SampleLimit = 25
)

$ErrorActionPreference = 'Stop'

function Test-Jq {
    if (Get-Command jq -ErrorAction SilentlyContinue) {
        return $true
    }

    if (Get-Command jq.exe -ErrorAction SilentlyContinue) {
        return $true
    }

    return $false
}

function Invoke-JqExample {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$Filter
    )

    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
    Write-Host "URL:    $Url"
    Write-Host "Filter: $Filter"

    $json = (Invoke-WebRequest -Uri $Url -UseBasicParsing).Content

    $jqArgs = @()
    if ($Compact) {
        $jqArgs += '-c'
    }
    $jqArgs += @($Filter)

    $json | & jq @jqArgs
    if ($LASTEXITCODE -ne 0) {
        throw "jq failed for URL: $Url"
    }
}

function Test-JqRule {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$Filter
    )

    try {
        $json = (Invoke-WebRequest -Uri $Url -UseBasicParsing).Content
    }
    catch {
        Write-Host "FAIL  $Title" -ForegroundColor Red
        Write-Host "      Could not fetch URL: $Url"
        return $false
    }

    $json | & jq -e $Filter | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAIL  $Title" -ForegroundColor Red
        Write-Host "      URL: $Url"
        Write-Host "      Rule: $Filter"
        return $false
    }

    Write-Host "PASS  $Title" -ForegroundColor Green
    return $true
}

function Validate-RegistryConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServersIndexUrl,

        [Parameter(Mandatory = $true)]
        [string]$ServerVersionsIndexUrl,

        [Parameter(Mandatory = $true)]
        [string]$ServerLatestUrl
    )

    Write-Host ""
    Write-Host "=== Configuration validation ===" -ForegroundColor Cyan

    $allChecksPassed = $true

    $allChecksPassed = (Test-JqRule -Title 'servers index has servers[] entries' -Url $ServersIndexUrl -Filter '.servers | type == "array" and length > 0') -and $allChecksPassed
    $allChecksPassed = (Test-JqRule -Title 'servers index includes metadata.count' -Url $ServersIndexUrl -Filter '.metadata.count | type == "number"') -and $allChecksPassed
    $allChecksPassed = (Test-JqRule -Title 'servers index entries expose required server fields' -Url $ServersIndexUrl -Filter 'all(.servers[]; ((.server.name // .server.id) | type == "string") and (.server.version | type == "string"))') -and $allChecksPassed
    $allChecksPassed = (Test-JqRule -Title 'servers index records include isLatest flag' -Url $ServersIndexUrl -Filter 'all(.servers[]; ._meta["io.modelcontextprotocol.registry/official"].isLatest | type == "boolean")') -and $allChecksPassed

    $allChecksPassed = (Test-JqRule -Title 'sample server versions index has at least one server record' -Url $ServerVersionsIndexUrl -Filter '.servers | type == "array" and length > 0') -and $allChecksPassed
    $allChecksPassed = (Test-JqRule -Title 'sample server versions index records include isLatest flag' -Url $ServerVersionsIndexUrl -Filter 'all(.servers[]; ._meta["io.modelcontextprotocol.registry/official"].isLatest | type == "boolean")') -and $allChecksPassed
    $allChecksPassed = (Test-JqRule -Title 'sample server versions index has at least one latest record' -Url $ServerVersionsIndexUrl -Filter '[.servers[] | ._meta["io.modelcontextprotocol.registry/official"].isLatest] | any') -and $allChecksPassed

    $allChecksPassed = (Test-JqRule -Title 'sample server latest endpoint has top-level server object' -Url $ServerLatestUrl -Filter '.server | type == "object"') -and $allChecksPassed
    $allChecksPassed = (Test-JqRule -Title 'sample server latest endpoint exposes id/name and version' -Url $ServerLatestUrl -Filter '((.server.name // .server.id) | type == "string") and (.server.version | type == "string")') -and $allChecksPassed

    if (-not $allChecksPassed) {
        throw "Configuration validation failed. One or more registry files are broken or missing required fields."
    }

    Write-Host "All validation checks passed." -ForegroundColor Green
}

function Get-ServerKey {
    param(
        [Parameter(Mandatory = $true)]
        [object]$ServerEntry,

        [Parameter(Mandatory = $true)]
        [ValidateSet('api', 'static')]
        [string]$Mode
    )

    if ($Mode -eq 'api') {
        return ($ServerEntry.server.name ?? $ServerEntry.server.id)
    }

    return ($ServerEntry.server.id ?? $ServerEntry.server.name)
}

function Resolve-RegistryLayout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$NormalizedRoot,

        [Parameter(Mandatory = $true)]
        [int]$SampleLimit
    )

    $apiServersIndexUrl = "$NormalizedRoot/v0/servers?limit=$SampleLimit"
    try {
        $apiPayload = (Invoke-WebRequest -Uri $apiServersIndexUrl -UseBasicParsing).Content | ConvertFrom-Json
        if ($null -ne $apiPayload.servers -and $apiPayload.servers.Count -gt 0) {
            return [PSCustomObject]@{
                Mode            = 'api'
                ServersIndexUrl = $apiServersIndexUrl
            }
        }
    }
    catch {
        # Fall through to static layout probe.
    }

    $staticServersIndexUrl = "$NormalizedRoot/v0.1/servers/index.json"
    try {
        $staticPayload = (Invoke-WebRequest -Uri $staticServersIndexUrl -UseBasicParsing).Content | ConvertFrom-Json
        if ($null -ne $staticPayload.servers -and $staticPayload.servers.Count -gt 0) {
            return [PSCustomObject]@{
                Mode            = 'static'
                ServersIndexUrl = $staticServersIndexUrl
            }
        }
    }
    catch {
        # Continue to final error.
    }

    throw "Could not discover a registry layout at '$NormalizedRoot'. Expected either v0 API (/v0/servers) or static docs layout (/v0.1/servers/index.json)."
}

function Resolve-SampleServerUrls {
    param(
        [Parameter(Mandatory = $true)]
        [string]$NormalizedRoot,

        [Parameter(Mandatory = $true)]
        [ValidateSet('api', 'static')]
        [string]$Mode,

        [Parameter(Mandatory = $true)]
        [string]$ServersIndexUrl,

        [Parameter(Mandatory = $true)]
        [int]$SampleLimit
    )

    $serversIndexPayload = (Invoke-WebRequest -Uri $ServersIndexUrl -UseBasicParsing).Content | ConvertFrom-Json
    if ($null -eq $serversIndexPayload.servers -or $serversIndexPayload.servers.Count -eq 0) {
        throw "No server entries found in servers index: $ServersIndexUrl"
    }

    $sampleServer = $serversIndexPayload.servers[0]
    $sampleServerKey = Get-ServerKey -ServerEntry $sampleServer -Mode $Mode
    if ([string]::IsNullOrWhiteSpace($sampleServerKey)) {
        throw "Sample server in '$ServersIndexUrl' is missing both server.name and server.id."
    }

    if ($Mode -eq 'api') {
        $encodedServerKey = [Uri]::EscapeDataString($sampleServerKey)
        return [PSCustomObject]@{
            SampleServerKey        = $sampleServerKey
            ServerVersionsIndexUrl = "$NormalizedRoot/v0/servers/$encodedServerKey/versions?limit=$SampleLimit"
            ServerLatestUrl        = "$NormalizedRoot/v0/servers/$encodedServerKey/versions/latest"
        }
    }

    return [PSCustomObject]@{
        SampleServerKey        = $sampleServerKey
        ServerVersionsIndexUrl = "$NormalizedRoot/v0.1/servers/$sampleServerKey/versions/index.json"
        ServerLatestUrl        = "$NormalizedRoot/v0.1/servers/$sampleServerKey/versions/latest/index.json"
    }
}

if (-not (Test-Jq)) {
    throw "jq is not installed or not on PATH. Install jq and rerun this script."
}

if (-not [Uri]::TryCreate($RegistryRoot, [UriKind]::Absolute, [ref]$null)) {
    throw "RegistryRoot must be an absolute URL, for example: http://localhost:8080"
}

$rootUri = [Uri]$RegistryRoot
if ($rootUri.Scheme -notin @('http', 'https')) {
    throw "RegistryRoot must use http or https."
}

if ($SampleLimit -le 0) {
    throw "SampleLimit must be a positive integer."
}

$normalizedRoot = $RegistryRoot.TrimEnd('/')
$layout = Resolve-RegistryLayout -NormalizedRoot $normalizedRoot -SampleLimit $SampleLimit
$sample = Resolve-SampleServerUrls `
    -NormalizedRoot $normalizedRoot `
    -Mode $layout.Mode `
    -ServersIndexUrl $layout.ServersIndexUrl `
    -SampleLimit $SampleLimit

Write-Host "MCP Registry jq navigation demo"
Write-Host "Registry root: $RegistryRoot"
Write-Host "Detected layout: $($layout.Mode)"
Write-Host "Sample server key: $($sample.SampleServerKey)"

Validate-RegistryConfiguration `
    -ServersIndexUrl $layout.ServersIndexUrl `
    -ServerVersionsIndexUrl $sample.ServerVersionsIndexUrl `
    -ServerLatestUrl $sample.ServerLatestUrl

Invoke-JqExample -Title 'List all server identifiers (name or id)' -Url $layout.ServersIndexUrl -Filter '.servers[].server | (.name // .id)'
Invoke-JqExample -Title 'List server title + description' -Url $layout.ServersIndexUrl -Filter '.servers[].server | {idOrName: (.name // .id), title, description}'
Invoke-JqExample -Title 'List transport endpoints by server' -Url $layout.ServersIndexUrl -Filter '.servers[].server | {idOrName: (.name // .id), remotes: [.remotes[]?.url // empty], stdioPackages: [.packages[]?.identifier // empty]}'
Invoke-JqExample -Title 'Show sample server versions index details' -Url $sample.ServerVersionsIndexUrl -Filter '.servers[] | {idOrName: (.server.name // .server.id), version: .server.version, isLatest: ._meta["io.modelcontextprotocol.registry/official"].isLatest}'
Invoke-JqExample -Title 'Show sample server latest metadata' -Url $sample.ServerLatestUrl -Filter '{idOrName: (.server.name // .server.id), title: .server.title, version: .server.version, remotes: [.server.remotes[]?.url // empty], packages: [.server.packages[]? | {registryType, identifier, version}]}'

Write-Host ""
Write-Host "Done. Edit run.ps1 to add your own jq filters." -ForegroundColor Green