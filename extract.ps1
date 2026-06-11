param(
    [string]$RegistryRoot = 'http://localhost:8080',
    [string]$OutputFolder = (Join-Path $PSScriptRoot 'docs'),
    [int]$PageLimit = 100
)

$ErrorActionPreference = 'Stop'

# Fallback body used when the source registry does not expose a 404 document.
$script:DefaultNotFoundBody = @'
{
  "error": "Not found",
  "message": "The requested MCP registry resource could not be found."
}
'@

function Get-RegistryString {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    return (Invoke-WebRequest -Uri $Url -UseBasicParsing).Content
}

function Save-RegistryFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    # Write UTF-8 without BOM so the static files match the original docs bytes.
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  wrote $Path"
}

function ConvertTo-RegistryJson {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject
    )

    return ($InputObject | ConvertTo-Json -Depth 100)
}

function Get-ServerId {
    param(
        [Parameter(Mandatory = $true)]
        [object]$ServerEntry
    )

    $id = $ServerEntry.server.id ?? $ServerEntry.server.name
    if ([string]::IsNullOrWhiteSpace($id)) {
        throw 'Encountered a server entry without server.id or server.name.'
    }

    # Static layout folders use a flat id; sanitize any path separators just in case.
    return ($id -replace '[\\/]', '_')
}

function Get-IsLatest {
    param(
        [Parameter(Mandatory = $true)]
        [object]$ServerEntry
    )

    return [bool]$ServerEntry._meta.'io.modelcontextprotocol.registry/official'.isLatest
}

function Resolve-RegistryLayout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$NormalizedRoot,

        [Parameter(Mandatory = $true)]
        [int]$PageLimit
    )

    $apiServersIndexUrl = "$NormalizedRoot/v0/servers?limit=$PageLimit"
    try {
        $apiPayload = (Invoke-WebRequest -Uri $apiServersIndexUrl -UseBasicParsing).Content | ConvertFrom-Json
        if ($null -ne $apiPayload.servers -and $apiPayload.servers.Count -gt 0) {
            return [PSCustomObject]@{ Mode = 'api' }
        }
    }
    catch {
        # Fall through to static layout probe.
    }

    $staticServersIndexUrl = "$NormalizedRoot/v0.1/servers/index.json"
    try {
        $staticPayload = (Invoke-WebRequest -Uri $staticServersIndexUrl -UseBasicParsing).Content | ConvertFrom-Json
        if ($null -ne $staticPayload.servers -and $staticPayload.servers.Count -gt 0) {
            return [PSCustomObject]@{ Mode = 'static' }
        }
    }
    catch {
        # Continue to final error.
    }

    throw "Could not discover a registry layout at '$NormalizedRoot'. Expected either v0 API (/v0/servers) or static docs layout (/v0.1/servers/index.json)."
}

function Get-ApiRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,

        [Parameter(Mandatory = $true)]
        [int]$PageLimit
    )

    $records = @()
    $cursor = $null

    do {
        $url = "$BaseUrl?limit=$PageLimit"
        if (-not [string]::IsNullOrWhiteSpace($cursor)) {
            $url += "&cursor=$([Uri]::EscapeDataString($cursor))"
        }

        $payload = (Invoke-WebRequest -Uri $url -UseBasicParsing).Content | ConvertFrom-Json
        if ($null -ne $payload.servers) {
            $records += $payload.servers
        }

        # The MCP registry uses "nextCursor"; tolerate the snake_case variant too.
        $cursor = $payload.metadata.nextCursor ?? $payload.metadata.next_cursor
    } while (-not [string]::IsNullOrWhiteSpace($cursor))

    return , $records
}

function Export-StaticLayout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$NormalizedRoot,

        [Parameter(Mandatory = $true)]
        [string]$OutputRoot
    )

    $serversIndexRaw = Get-RegistryString -Url "$NormalizedRoot/v0.1/servers/index.json"
    Save-RegistryFile -Path (Join-Path $OutputRoot 'v0.1/servers/index.json') -Content $serversIndexRaw

    $serversIndex = $serversIndexRaw | ConvertFrom-Json
    $serverCount = 0

    foreach ($entry in $serversIndex.servers) {
        $id = Get-ServerId -ServerEntry $entry
        Write-Host "Extracting server '$id'..."

        $versionsIndexRaw = Get-RegistryString -Url "$NormalizedRoot/v0.1/servers/$id/versions/index.json"
        Save-RegistryFile -Path (Join-Path $OutputRoot "v0.1/servers/$id/versions/index.json") -Content $versionsIndexRaw

        $versionsIndex = $versionsIndexRaw | ConvertFrom-Json
        foreach ($versionEntry in $versionsIndex.servers) {
            $version = $versionEntry.server.version
            if ([string]::IsNullOrWhiteSpace($version)) {
                throw "Server '$id' has a version record without server.version."
            }

            $versionRaw = Get-RegistryString -Url "$NormalizedRoot/v0.1/servers/$id/versions/$version/index.json"
            Save-RegistryFile -Path (Join-Path $OutputRoot "v0.1/servers/$id/versions/$version/index.json") -Content $versionRaw
        }

        $latestRaw = Get-RegistryString -Url "$NormalizedRoot/v0.1/servers/$id/versions/latest/index.json"
        Save-RegistryFile -Path (Join-Path $OutputRoot "v0.1/servers/$id/versions/latest/index.json") -Content $latestRaw

        $serverCount++
    }

    return $serverCount
}

function Export-ApiLayout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$NormalizedRoot,

        [Parameter(Mandatory = $true)]
        [string]$OutputRoot,

        [Parameter(Mandatory = $true)]
        [int]$PageLimit
    )

    $servers = Get-ApiRecords -BaseUrl "$NormalizedRoot/v0/servers" -PageLimit $PageLimit
    $serversIndex = [ordered]@{
        servers  = $servers
        metadata = [ordered]@{ count = $servers.Count }
    }
    Save-RegistryFile -Path (Join-Path $OutputRoot 'v0.1/servers/index.json') -Content (ConvertTo-RegistryJson -InputObject $serversIndex)

    $serverCount = 0

    foreach ($entry in $servers) {
        $id = Get-ServerId -ServerEntry $entry
        $name = $entry.server.name ?? $entry.server.id
        $encodedName = [Uri]::EscapeDataString($name)
        Write-Host "Extracting server '$id'..."

        $versions = Get-ApiRecords -BaseUrl "$NormalizedRoot/v0/servers/$encodedName/versions" -PageLimit $PageLimit
        $versionsIndex = [ordered]@{
            servers  = $versions
            metadata = [ordered]@{ count = $versions.Count }
        }
        Save-RegistryFile -Path (Join-Path $OutputRoot "v0.1/servers/$id/versions/index.json") -Content (ConvertTo-RegistryJson -InputObject $versionsIndex)

        foreach ($versionEntry in $versions) {
            $version = $versionEntry.server.version
            if ([string]::IsNullOrWhiteSpace($version)) {
                throw "Server '$id' has a version record without server.version."
            }

            $versionJson = ConvertTo-RegistryJson -InputObject $versionEntry
            Save-RegistryFile -Path (Join-Path $OutputRoot "v0.1/servers/$id/versions/$version/index.json") -Content $versionJson

            if (Get-IsLatest -ServerEntry $versionEntry) {
                Save-RegistryFile -Path (Join-Path $OutputRoot "v0.1/servers/$id/versions/latest/index.json") -Content $versionJson
            }
        }

        $serverCount++
    }

    return $serverCount
}

if (-not [Uri]::TryCreate($RegistryRoot, [UriKind]::Absolute, [ref]$null)) {
    throw "RegistryRoot must be an absolute URL, for example: https://mystorage.z6.web.core.windows.net"
}

$rootUri = [Uri]$RegistryRoot
if ($rootUri.Scheme -notin @('http', 'https')) {
    throw 'RegistryRoot must use http or https.'
}

if ($PageLimit -le 0) {
    throw 'PageLimit must be a positive integer.'
}

$normalizedRoot = $RegistryRoot.TrimEnd('/')
$outputRoot = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $OutputFolder))

$layout = Resolve-RegistryLayout -NormalizedRoot $normalizedRoot -PageLimit $PageLimit

Write-Host 'MCP Registry static extraction'
Write-Host "Registry root:  $RegistryRoot"
Write-Host "Detected layout: $($layout.Mode)"
Write-Host "Output folder:  $outputRoot"
Write-Host ''

switch ($layout.Mode) {
    'static' {
        $serverCount = Export-StaticLayout -NormalizedRoot $normalizedRoot -OutputRoot $outputRoot
    }
    'api' {
        $serverCount = Export-ApiLayout -NormalizedRoot $normalizedRoot -OutputRoot $outputRoot -PageLimit $PageLimit
    }
}

# Mirror the 404 document so the extracted folder is a complete static site.
$notFoundBody = $script:DefaultNotFoundBody
try {
    $notFoundBody = Get-RegistryString -Url "$normalizedRoot/404.json"
}
catch {
    Write-Host '  source 404.json not available; writing default 404 body.'
}
Save-RegistryFile -Path (Join-Path $outputRoot '404.json') -Content $notFoundBody

Write-Host ''
Write-Host "Done. Extracted $serverCount server(s) into '$outputRoot'." -ForegroundColor Green
