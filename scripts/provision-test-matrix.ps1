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
        [string] $Url,
        [string] $ExpectedSha256 = ""
    )

    $path = Join-Path $cacheRoot $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Host "Downloading $Name"
        Invoke-WebRequest -Uri $Url -OutFile $path -Headers @{ "User-Agent" = $userAgent } -UseBasicParsing
    }
    if ($ExpectedSha256) {
        $actualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
        if ($actualSha256 -ne $ExpectedSha256) {
            throw "$Name has SHA-256 $actualSha256, expected $ExpectedSha256"
        }
    }
    return $path
}

$worldEdit12110 = Get-PinnedFile `
    -Name "worldedit-bukkit-7.4.2.jar" `
    -Url "https://cdn.modrinth.com/data/1u6JkXh5/versions/p8T2aZ8U/worldedit-bukkit-7.4.2.jar" `
    -ExpectedSha256 "0EE152B1BE5DFB51500505E2BF5A8C9D66F09C7FA484BF9AEA384D7E7B459B06"
$worldGuard12110 = Get-PinnedFile `
    -Name "worldguard-bukkit-7.0.15-SNAPSHOT-dist.jar" `
    -Url "https://github.com/Inquisitors-transfers/WorldGuard-Folia/releases/download/2026-02-02/worldguard-bukkit-7.0.15-SNAPSHOT-dist.jar" `
    -ExpectedSha256 "0EE453113F45AD4129852FA9334789CC6A1F4700BE3FF9396F11FFC6787E02E1"
$worldEdit262 = Get-PinnedFile `
    -Name "worldedit-bukkit-7.4.4.jar" `
    -Url "https://cdn.modrinth.com/data/1u6JkXh5/versions/qNuPcliz/worldedit-bukkit-7.4.4.jar" `
    -ExpectedSha256 "44C97EE6C1DF9AFA127DF3C5A2C6A7108F826FB44AB7B255A7EC4250FEB89B9D"
$worldGuard262 = Get-PinnedFile `
    -Name "worldguard-bukkit-7.0.17.jar" `
    -Url "https://cdn.modrinth.com/data/DKY9btbd/versions/pI4UHLJL/worldguard-bukkit-7.0.17.jar" `
    -ExpectedSha256 "3F14562509BF01E7680571B6F56932239157FF938F257C3226DF3B4088AE54F2"
$purpur12110 = Get-PinnedFile `
    -Name "purpur-1.21.10-2535.jar" `
    -Url "https://api.purpurmc.org/v2/purpur/1.21.10/2535/download" `
    -ExpectedSha256 "4159783677B08B6395782E6150CB28646C70ED988B7948C09E01AA5A5E90F548"
$purpur262 = Get-PinnedFile `
    -Name "purpur-26.2-2614.jar" `
    -Url "https://api.purpurmc.org/v2/purpur/26.2/2614/download" `
    -ExpectedSha256 "27189194D00B93BDF94045F08423D6E3D55D89DE3519E6548FB5A56CA99DCEA7"
$folia2612 = Get-PinnedFile `
    -Name "folia-26.1.2-8.jar" `
    -Url "https://fill-data.papermc.io/v1/objects/607afd1c3320008e1ffd2eaee6780ace4419d5f8c527b75e79f259be79ebf57b/folia-26.1.2-8.jar" `
    -ExpectedSha256 "607AFD1C3320008E1FFD2EAEE6780ACE4419D5F8C527B75E79F259BE79EBF57B"

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
        Name = "folia-26.1.2-protectionstones-smoke"
        Port = 25583
        Java = 25
        Server = $folia2612
        ServerId = "Folia 26.1.2 build 8"
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

Write-Host "Provisioned the three required release lanes under $serversRoot"
