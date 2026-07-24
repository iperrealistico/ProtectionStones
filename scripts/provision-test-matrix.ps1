param(
    [string] $CandidateJar = "",
    [switch] $AcceptEula
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $repoRoot
$serversRoot = Join-Path $workspaceRoot "local-servers"
$cacheRoot = Join-Path $serversRoot ".protectionstones-cache"

if ([string]::IsNullOrWhiteSpace($CandidateJar)) {
    $CandidateJar = Join-Path $repoRoot "target/ProtectionStones-2.10.6-pvc.1.jar"
}
$CandidateJar = [System.IO.Path]::GetFullPath($CandidateJar)
if (-not (Test-Path -LiteralPath $CandidateJar -PathType Leaf)) {
    throw "Candidate JAR not found: $CandidateJar"
}

New-Item -ItemType Directory -Force -Path $cacheRoot | Out-Null
$userAgent = "ProtectionStones-PVC-test-matrix/2.10.6-pvc.1"

function Get-PinnedFile {
    param(
        [string] $Name,
        [string] $Url
    )

    $path = Join-Path $cacheRoot $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Host "Downloading $Name"
        Invoke-WebRequest -Uri $Url -OutFile $path -Headers @{ "User-Agent" = $userAgent } -UseBasicParsing
    }
    return $path
}

$worldEdit12110 = Get-PinnedFile `
    -Name "worldedit-bukkit-7.4.2.jar" `
    -Url "https://cdn.modrinth.com/data/1u6JkXh5/versions/p8T2aZ8U/worldedit-bukkit-7.4.2.jar"
$worldGuard12110 = Get-PinnedFile `
    -Name "worldguard-bukkit-7.0.15-SNAPSHOT-dist.jar" `
    -Url "https://github.com/Inquisitors-transfers/WorldGuard-Folia/releases/download/2026-02-02/worldguard-bukkit-7.0.15-SNAPSHOT-dist.jar"
$worldEdit262 = Get-PinnedFile `
    -Name "worldedit-bukkit-7.4.4.jar" `
    -Url "https://cdn.modrinth.com/data/1u6JkXh5/versions/qNuPcliz/worldedit-bukkit-7.4.4.jar"
$worldGuard262 = Get-PinnedFile `
    -Name "worldguard-bukkit-7.0.17.jar" `
    -Url "https://cdn.modrinth.com/data/DKY9btbd/versions/pI4UHLJL/worldguard-bukkit-7.0.17.jar"
$purpur12110 = Get-PinnedFile `
    -Name "purpur-1.21.10-2535.jar" `
    -Url "https://api.purpurmc.org/v2/purpur/1.21.10/2535/download"
$purpur262 = Get-PinnedFile `
    -Name "purpur-26.2-2614.jar" `
    -Url "https://api.purpurmc.org/v2/purpur/26.2/2614/download"

$folia262 = Join-Path $serversRoot ".sources/folia-26.2/folia-server/build/libs/folia-paperclip-26.2.local-SNAPSHOT.jar"
if (-not (Test-Path -LiteralPath $folia262 -PathType Leaf)) {
    throw "Folia 26.2 source-built Paperclip is missing: $folia262"
}

$lanes = @(
    @{
        Name = "purpur-1.21.10-protectionstones-smoke"
        Port = 25581
        Java = 21
        Server = $purpur12110
        ServerId = "Purpur 1.21.10 build 2535"
        Dependencies = @($worldEdit12110, $worldGuard12110)
    },
    @{
        Name = "purpur-26.2-protectionstones-smoke"
        Port = 25582
        Java = 25
        Server = $purpur262
        ServerId = "Purpur 26.2 build 2614"
        Dependencies = @($worldEdit262, $worldGuard262)
    },
    @{
        Name = "folia-26.2-protectionstones-smoke"
        Port = 25584
        Java = 25
        Server = $folia262
        ServerId = "Folia 26.2 source commit 602048cb815db2ded68cca8cd43f480b983185a1"
        Dependencies = @($worldEdit262, $worldGuard262)
    }
)

foreach ($lane in $lanes) {
    $root = Join-Path $serversRoot $lane.Name
    $plugins = Join-Path $root "plugins"
    New-Item -ItemType Directory -Force -Path $plugins | Out-Null

    Get-ChildItem -LiteralPath $plugins -File | Where-Object {
        $_.Name -like "ProtectionStones-*.jar" -or
        $_.Name -like "worldedit-bukkit-*.jar" -or
        $_.Name -like "worldguard-bukkit-*.jar"
    } | Remove-Item -Force

    Copy-Item -LiteralPath $lane.Server -Destination (Join-Path $root "server.jar") -Force
    foreach ($dependency in $lane.Dependencies) {
        Copy-Item -LiteralPath $dependency -Destination (Join-Path $plugins (Split-Path -Leaf $dependency)) -Force
    }
    Copy-Item -LiteralPath $CandidateJar -Destination (Join-Path $plugins (Split-Path -Leaf $CandidateJar)) -Force

    if ($AcceptEula) {
        Set-Content -LiteralPath (Join-Path $root "eula.txt") -Value "eula=true" -Encoding ascii
    }

    @(
        "server-ip=127.0.0.1"
        "server-port=$($lane.Port)"
        "online-mode=false"
        "spawn-protection=0"
        "view-distance=4"
        "simulation-distance=4"
        "enable-rcon=false"
        "motd=ProtectionStones isolated smoke lane"
    ) | Set-Content -LiteralPath (Join-Path $root "server.properties") -Encoding ascii

    $files = @(
        (Join-Path $root "server.jar")
        (Join-Path $plugins (Split-Path -Leaf $CandidateJar))
    ) + ($lane.Dependencies | ForEach-Object { Join-Path $plugins (Split-Path -Leaf $_) })

    $manifest = [ordered]@{
        lane = $lane.Name
        server = $lane.ServerId
        java = $lane.Java
        port = $lane.Port
        provisioned_at = (Get-Date -Format o)
        files = @($files | ForEach-Object {
            [ordered]@{
                name = Split-Path -Leaf $_
                bytes = (Get-Item -LiteralPath $_).Length
                sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash
            }
        })
    }
    $manifest | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $root "lane-manifest.json") -Encoding utf8
}

$blockedRoot = Join-Path $serversRoot "folia-1.21.10-protectionstones-smoke"
New-Item -ItemType Directory -Force -Path $blockedRoot | Out-Null
@'
# BLOCKED: no Folia 1.21.10 runtime

PaperMC's Folia project has no published 1.21.10 build and no `ver/1.21.10`
source branch. The official Fill catalog omits 1.21.10, and a direct version
query returns null. In source history, commit e1120c1436f9a4a0f849a22ec8c62c7a1e02b74c
still declares mcVersion=1.21.8; its direct child
8bfaa08bec8dfc0b55ab78b82b56dde20d3f55ba declares mcVersion=1.21.11.

Neither adjacent version nor a locally invented server port is an acceptable
substitute for the exact required lane.

Checked: 2026-07-24
'@ | Set-Content -LiteralPath (Join-Path $blockedRoot "BLOCKED.md") -Encoding utf8

Write-Host "Provisioned three runnable lanes under $serversRoot"
Write-Warning "Folia 1.21.10 remains blocked because no exact server implementation exists."
