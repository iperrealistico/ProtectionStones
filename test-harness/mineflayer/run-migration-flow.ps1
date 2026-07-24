param(
    [string] $Lane = "purpur-1.21.10-protectionstones-upstream-migration",
    [Parameter(Mandatory = $true)]
    [string] $JavaExe,
    [int] $Port = 25586,
    [int] $BaseX = 8000,
    [int] $BaseZ = 1000,
    [string] $ExpectedCandidateSha256 = "",
    [string] $NodeExe = "node"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$workspaceRoot = Split-Path $repoRoot -Parent
$sourceLane = Join-Path $workspaceRoot "local-servers/purpur-1.21.10-protectionstones-smoke"
$localServersRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $workspaceRoot "local-servers")
)
$serverRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $localServersRoot $Lane)
)
$expectedPrefix = $localServersRoot.TrimEnd("\") + "\"
if (-not $serverRoot.StartsWith(
    $expectedPrefix,
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw "Migration root is outside local-servers: $serverRoot"
}

$nodeScript = Join-Path $PSScriptRoot "migration-flow.mjs"
$upstreamJar = Join-Path $workspaceRoot (
    ".ai-control/workspace-local/protectionstones-upstream-api-89be4ae/" +
    "target/protectionstones-2.10.6.jar"
)
$candidateJar = Join-Path $repoRoot "target/ProtectionStones-2.10.6-pvc.1.jar"
foreach ($path in @($JavaExe, $nodeScript, $upstreamJar, $candidateJar)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file not found: $path"
    }
}
if (-not (Get-Command $NodeExe -ErrorAction SilentlyContinue)) {
    throw "Node executable not found: $NodeExe"
}

$upstreamHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $upstreamJar).Hash
$candidateHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidateJar).Hash
if ($ExpectedCandidateSha256 -and $candidateHash -ne $ExpectedCandidateSha256) {
    throw "Candidate hash $candidateHash does not match $ExpectedCandidateSha256"
}

if (Test-Path -LiteralPath $serverRoot) {
    Remove-Item -LiteralPath $serverRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path (
    Join-Path $serverRoot "plugins"
) | Out-Null

foreach ($name in @(
    "server.jar",
    "eula.txt",
    "bukkit.yml",
    "commands.yml",
    "help.yml",
    "permissions.yml",
    "server.properties",
    "spigot.yml",
    "wepif.yml"
)) {
    Copy-Item -LiteralPath (Join-Path $sourceLane $name) -Destination $serverRoot
}

$pluginsRoot = Join-Path $serverRoot "plugins"
$dependencyNames = @(
    "worldedit-bukkit-7.4.2.jar",
    "worldguard-bukkit-7.0.15-SNAPSHOT-dist.jar",
    "ProtectionStonesTestVault.jar",
    "PlaceholderAPI-2.12.2.jar"
)
foreach ($name in $dependencyNames) {
    Copy-Item -LiteralPath (
        Join-Path $sourceLane "plugins/$name"
    ) -Destination $pluginsRoot
}

$serverPropertiesPath = Join-Path $serverRoot "server.properties"
$serverProperties = [System.IO.File]::ReadAllText($serverPropertiesPath)
$serverProperties = [regex]::Replace(
    $serverProperties,
    "(?m)^server-port=.*$",
    "server-port=$Port"
)
[System.IO.File]::WriteAllText(
    $serverPropertiesPath,
    $serverProperties,
    [System.Text.UTF8Encoding]::new($false)
)

$activePlugin = Join-Path $pluginsRoot "ProtectionStones.jar"
Copy-Item -LiteralPath $upstreamJar -Destination $activePlugin

function Invoke-MigrationPhase {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("create", "verify")]
        [string] $Mode,
        [Parameter(Mandatory = $true)]
        [string] $Phase
    )

    $logPath = Join-Path $serverRoot "logs/latest.log"
    if (Test-Path -LiteralPath $logPath -PathType Leaf) {
        Move-Item -LiteralPath $logPath -Destination (
            Join-Path $serverRoot "logs/$Phase-previous.log"
        )
    }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $JavaExe
    $startInfo.WorkingDirectory = $serverRoot
    $startInfo.Arguments = "-Xms1G -Xmx2G -jar server.jar --nogui"
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $server = [System.Diagnostics.Process]::new()
    $server.StartInfo = $startInfo
    if (-not $server.Start()) {
        throw "Failed to start migration phase $Phase"
    }

    $stdout = $server.StandardOutput.ReadToEndAsync()
    $stderr = $server.StandardError.ReadToEndAsync()
    $phaseSucceeded = $false
    try {
        $deadline = (Get-Date).AddSeconds(180)
        $ready = $false
        while (-not $server.HasExited -and (Get-Date) -lt $deadline) {
            if (Test-Path -LiteralPath $logPath) {
                $log = Get-Content -Raw -LiteralPath $logPath
                if ($log -match "Done \(") {
                    $ready = $true
                    break
                }
            }
            Start-Sleep -Seconds 1
        }
        if (-not $ready) {
            throw "Migration phase $Phase did not reach ready state"
        }

        $server.StandardInput.WriteLine("op PSOwner")
        $server.StandardInput.WriteLine("op PSMember")
        Start-Sleep -Seconds 1

        & $NodeExe $nodeScript $Mode $Port PSOwner PSMember $BaseX $BaseZ 120000 *>&1 |
            Tee-Object -FilePath (Join-Path $serverRoot "$Phase-bot.log")
        if ($LASTEXITCODE -ne 0) {
            throw "Migration phase $Phase failed with exit $LASTEXITCODE"
        }
        $phaseSucceeded = $true
    } finally {
        if (-not $server.HasExited) {
            $server.StandardInput.WriteLine("stop")
            if (-not $server.WaitForExit(60000)) {
                $server.Kill($true)
                throw "Migration phase $Phase did not stop"
            }
        }
        ($stdout.Result + [Environment]::NewLine + $stderr.Result) |
            Set-Content -LiteralPath (
                Join-Path $serverRoot "$Phase-console.log"
            ) -Encoding utf8
    }

    if ($phaseSucceeded) {
        Copy-Item -LiteralPath $logPath -Destination (
            Join-Path $serverRoot "logs/$Phase-pass.log"
        ) -Force
    }
}

function Get-PluginDataHashes {
    $dataRoot = Join-Path $pluginsRoot "ProtectionStones"
    $result = [ordered]@{}
    Get-ChildItem -LiteralPath $dataRoot -Recurse -File |
        Where-Object { $_.Extension -in @(".toml", ".yml", ".yaml") } |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($dataRoot.Length + 1)
            $result[$relative] = (
                Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName
            ).Hash
        }
    return $result
}

Invoke-MigrationPhase -Mode create -Phase "upstream-create"
$baselineDataHashes = Get-PluginDataHashes
$baselineDataHashes | ConvertTo-Json |
    Set-Content -LiteralPath (
        Join-Path $serverRoot "upstream-plugin-data-hashes.json"
    ) -Encoding utf8

New-Item -ItemType Directory -Force -Path (
    Join-Path $serverRoot "source-artifacts"
) | Out-Null
Move-Item -LiteralPath $activePlugin -Destination (
    Join-Path $serverRoot "source-artifacts/ProtectionStones-upstream-2.10.6.jar"
)
Copy-Item -LiteralPath $candidateJar -Destination $activePlugin

Invoke-MigrationPhase -Mode verify -Phase "candidate-verify-1"
$firstCandidateDataHashes = Get-PluginDataHashes
Invoke-MigrationPhase -Mode verify -Phase "candidate-verify-2"
$secondCandidateDataHashes = Get-PluginDataHashes

$baselineJson = $baselineDataHashes | ConvertTo-Json -Compress
$firstJson = $firstCandidateDataHashes | ConvertTo-Json -Compress
$secondJson = $secondCandidateDataHashes | ConvertTo-Json -Compress
if ($firstJson -ne $baselineJson -or $secondJson -ne $baselineJson) {
    throw "Candidate changed upstream ProtectionStones TOML/YAML data"
}

$fatalPatterns = @(
    "Error occurred while enabling ProtectionStones",
    "NoClassDefFoundError",
    "NoSuchMethodError",
    "LinkageError",
    "IllegalStateException:.*thread",
    "TickThread.*failed",
    "thread violation"
)
foreach ($phase in @("upstream-create", "candidate-verify-1", "candidate-verify-2")) {
    $log = Get-Content -Raw -LiteralPath (
        Join-Path $serverRoot "logs/$phase-pass.log"
    )
    foreach ($pattern in $fatalPatterns) {
        if ($log -match $pattern) {
            throw "$phase contains fatal evidence: $pattern"
        }
    }
}

$manifest = [ordered]@{
    purpose = "ProtectionStones upstream 2.10.6 in-place migration verification"
    upstream_commit = "89be4aeab1f00422ad060e797660e56f32e1aaf0"
    upstream_sha256 = $upstreamHash
    candidate_sha256 = $candidateHash
    server = "Purpur 1.21.10 build 2535"
    java = 21
    port = $Port
    phases = @("upstream-create", "candidate-verify-1", "candidate-verify-2")
    plugin_data_hashes_unchanged = $true
}
$manifest | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath (
        Join-Path $serverRoot "migration-manifest.json"
    ) -Encoding utf8

Write-Host (
    "PASS: upstream data migrated twice; upstream=$upstreamHash; " +
    "candidate=$candidateHash; plugin-data-files=$($baselineDataHashes.Count)"
)
