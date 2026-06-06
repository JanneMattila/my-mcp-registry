param(
    [string]$RegistryRoot = 'http://localhost:60720',
    [switch]$Compact
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
        [string]$GithubVersionsUrl,

        [Parameter(Mandatory = $true)]
        [string]$LearnVersionsUrl,

        [Parameter(Mandatory = $true)]
        [string]$PlaywrightLatestUrl
    )

    Write-Host ""
    Write-Host "=== Configuration validation ===" -ForegroundColor Cyan

    $allChecksPassed = $true

    $allChecksPassed = (Test-JqRule -Title 'servers/index.json has servers[] entries' -Url $ServersIndexUrl -Filter '.servers | type == "array" and length > 0') -and $allChecksPassed
    $allChecksPassed = (Test-JqRule -Title 'servers/index.json entries expose required server fields' -Url $ServersIndexUrl -Filter 'all(.servers[]; (.server.id | type == "string") and (.server.title | type == "string") and (.server.version | type == "string"))') -and $allChecksPassed
    $allChecksPassed = (Test-JqRule -Title 'servers/index.json includes metadata.count' -Url $ServersIndexUrl -Filter '.metadata.count | type == "number"') -and $allChecksPassed

    $allChecksPassed = (Test-JqRule -Title 'github versions index has at least one server record' -Url $GithubVersionsUrl -Filter '.servers | type == "array" and length > 0') -and $allChecksPassed
    $allChecksPassed = (Test-JqRule -Title 'github versions index records include isLatest flag' -Url $GithubVersionsUrl -Filter 'all(.servers[]; ._meta["io.modelcontextprotocol.registry/official"].isLatest | type == "boolean")') -and $allChecksPassed

    $allChecksPassed = (Test-JqRule -Title 'microsoft-learn versions index has at least one latest record' -Url $LearnVersionsUrl -Filter '[.servers[] | ._meta["io.modelcontextprotocol.registry/official"].isLatest] | any') -and $allChecksPassed

    $allChecksPassed = (Test-JqRule -Title 'playwright latest has top-level server object' -Url $PlaywrightLatestUrl -Filter '.server | type == "object"') -and $allChecksPassed
    $allChecksPassed = (Test-JqRule -Title 'playwright latest exposes server id and version' -Url $PlaywrightLatestUrl -Filter '(.server.id | type == "string") and (.server.version | type == "string")') -and $allChecksPassed

    if (-not $allChecksPassed) {
        throw "Configuration validation failed. One or more registry files are broken or missing required fields."
    }

    Write-Host "All validation checks passed." -ForegroundColor Green
}

if (-not (Test-Jq)) {
    throw "jq is not installed or not on PATH. Install jq and rerun this script."
}

if (-not [Uri]::TryCreate($RegistryRoot, [UriKind]::Absolute, [ref]$null)) {
    throw "RegistryRoot must be an absolute URL, for example: http://localhost:60883"
}

$rootUri = [Uri]$RegistryRoot
if ($rootUri.Scheme -notin @('http', 'https')) {
    throw "RegistryRoot must use http or https."
}

$normalizedRoot = $RegistryRoot.TrimEnd('/')

$serversIndex = "$normalizedRoot/v0.1/servers/index.json"
$githubVersionsIndex = "$normalizedRoot/v0.1/servers/github/versions/index.json"
$learnVersionsIndex = "$normalizedRoot/v0.1/servers/microsoft-learn/versions/index.json"
$playwrightLatest = "$normalizedRoot/v0.1/servers/playwright-mcp/versions/latest/index.json"

Write-Host "MCP Registry jq navigation demo"
Write-Host "Registry root: $RegistryRoot"

Validate-RegistryConfiguration `
    -ServersIndexUrl $serversIndex `
    -GithubVersionsUrl $githubVersionsIndex `
    -LearnVersionsUrl $learnVersionsIndex `
    -PlaywrightLatestUrl $playwrightLatest

Invoke-JqExample -Title 'List all server IDs' -Url $serversIndex -Filter '.servers[].server.id'
Invoke-JqExample -Title 'List server title + description' -Url $serversIndex -Filter '.servers[].server | {id, title, description}'
Invoke-JqExample -Title 'List transport endpoints by server' -Url $serversIndex -Filter '.servers[].server | {id, remotes: [.remotes[]?.url // empty], stdioPackages: [.packages[]?.identifier // empty]}'
Invoke-JqExample -Title 'Show GitHub versions index details' -Url $githubVersionsIndex -Filter '.servers[] | {id: .server.id, version: .server.version, isLatest: ._meta["io.modelcontextprotocol.registry/official"].isLatest}'
Invoke-JqExample -Title 'Show Microsoft Learn latest entry' -Url $learnVersionsIndex -Filter '.servers[] | select(._meta["io.modelcontextprotocol.registry/official"].isLatest == true) | {id: .server.id, version: .server.version, remoteUrls: [.server.remotes[]?.url // empty]}'
Invoke-JqExample -Title 'Show Playwright latest metadata' -Url $playwrightLatest -Filter '{id: .server.id, title: .server.title, name: .server.name, packages: [.server.packages[]? | {registryType, identifier, version}]}'

Write-Host ""
Write-Host "Done. Edit run.ps1 to add your own jq filters." -ForegroundColor Green
