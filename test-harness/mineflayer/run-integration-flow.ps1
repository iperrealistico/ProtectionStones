param(
    [Parameter(Mandatory = $true)]
    [string] $Lane,
    [Parameter(Mandatory = $true)]
    [string] $JavaExe,
    [Parameter(Mandatory = $true)]
    [int] $Port,
    [Parameter(Mandatory = $true)]
    [int] $BaseX,
    [int] $BaseZ = 1000,
    [string] $ExpectedCandidateSha256 = "",
    [string] $NodeExe = "node"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$workspaceRoot = Split-Path $repoRoot -Parent
$serverRoot = Join-Path $workspaceRoot "local-servers/$Lane"
$manifestPath = Join-Path $serverRoot "lane-manifest.json"
$nodeScript = Join-Path $PSScriptRoot "integration-flow.mjs"
$pluginsRoot = Join-Path $serverRoot "plugins"
$candidatePath = Join-Path $pluginsRoot "ProtectionStones-2.10.6-pvc.1.jar"
$probeSource = Join-Path $repoRoot (
    "test-harness/integration-probe/target/ProtectionStonesIntegrationProbe.jar"
)
$probeTarget = Join-Path $pluginsRoot "ProtectionStonesIntegrationProbe.jar"
$configPath = Join-Path $pluginsRoot "ProtectionStones/config.toml"
$blockPath = Join-Path $pluginsRoot "ProtectionStones/blocks/block1.toml"

foreach ($path in @(
    $JavaExe,
    $manifestPath,
    $nodeScript,
    $candidatePath,
    $probeSource,
    $configPath,
    $blockPath
)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file not found: $path"
    }
}
if (-not (Get-Command $NodeExe -ErrorAction SilentlyContinue)) {
    throw "Node executable not found: $NodeExe"
}
if (-not (Get-ChildItem -LiteralPath $pluginsRoot -File | Where-Object {
    $_.Name -like "PlaceholderAPI-*.jar"
})) {
    throw "PlaceholderAPI is not installed in $Lane"
}
foreach ($dependency in @(
    "LuckPerms-Bukkit-5.5.65.jar",
    "ProtectionStonesTestVault.jar"
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $pluginsRoot $dependency) -PathType Leaf)) {
        throw "$dependency is not installed in $Lane"
    }
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$candidate = $manifest.files | Where-Object {
    $_.name -eq "ProtectionStones-2.10.6-pvc.1.jar"
}
if (-not $candidate) {
    throw "Candidate is missing from the lane manifest."
}
$installedCandidateHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidatePath).Hash
if ($candidate.sha256 -ne $installedCandidateHash) {
    throw "Installed candidate does not match the lane manifest."
}
if ($ExpectedCandidateSha256 -and $installedCandidateHash -ne $ExpectedCandidateSha256) {
    throw "Lane candidate hash $installedCandidateHash does not match $ExpectedCandidateSha256"
}

Copy-Item -LiteralPath $probeSource -Destination $probeTarget -Force
$probeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $probeTarget).Hash
$configBytes = [System.IO.File]::ReadAllBytes($configPath)
$blockBytes = [System.IO.File]::ReadAllBytes($blockPath)
$configOriginalHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $configPath).Hash
$blockOriginalHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $blockPath).Hash

$configText = [System.IO.File]::ReadAllText($configPath)
$updatedConfigText = $configText.Replace("tax_enabled = false", "tax_enabled = true")
if ($updatedConfigText -eq $configText) {
    throw "Could not enable taxes in $configPath"
}

$blockText = [System.IO.File]::ReadAllText($blockPath)
$updatedBlockText = $blockText.Replace(
    "tax_amount = 0.0",
    "tax_amount = 25.0"
)
$updatedBlockText = $updatedBlockText.Replace(
    "tax_period = -1",
    "tax_period = 3600"
)
$updatedBlockText = $updatedBlockText.Replace(
    "start_with_tax_autopay = true",
    "start_with_tax_autopay = false"
)
if ($updatedBlockText -eq $blockText) {
    throw "Could not configure deterministic taxes in $blockPath"
}

[System.IO.File]::WriteAllText(
    $configPath,
    $updatedConfigText,
    [System.Text.UTF8Encoding]::new($false)
)
[System.IO.File]::WriteAllText(
    $blockPath,
    $updatedBlockText,
    [System.Text.UTF8Encoding]::new($false)
)

$logPath = Join-Path $serverRoot "logs/latest.log"
if (Test-Path -LiteralPath $logPath -PathType Leaf) {
    $previous = "integration-previous-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss")
    Move-Item -LiteralPath $logPath -Destination (Join-Path $serverRoot "logs/$previous")
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
$stdout = $null
$stderr = $null
$flowSucceeded = $false

try {
    if (-not $server.Start()) {
        throw "Failed to start $Lane"
    }
    $stdout = $server.StandardOutput.ReadToEndAsync()
    $stderr = $server.StandardError.ReadToEndAsync()

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
        throw "$Lane did not reach ready state"
    }

    $server.StandardInput.WriteLine("op PSOwner")
    $server.StandardInput.WriteLine("op PSMember")
    $server.StandardInput.WriteLine(
        "lp user PSOwner permission unset protectionstones.limit.1"
    )
    $server.StandardInput.WriteLine(
        "lp user PSOwner permission unset protectionstones.admin"
    )
    Start-Sleep -Seconds 1

    $botOutput = Join-Path $serverRoot "integration-bot.log"
    & $NodeExe $nodeScript $Port PSOwner PSMember $BaseX $BaseZ 240000 *>&1 |
        Tee-Object -FilePath $botOutput
    if ($LASTEXITCODE -ne 0) {
        throw "$Lane integration bot flow failed with exit $LASTEXITCODE"
    }
    $flowSucceeded = $true
} finally {
    if ($server -and -not $server.HasExited) {
        $server.StandardInput.WriteLine(
            "lp user PSOwner permission unset protectionstones.limit.1"
        )
        $server.StandardInput.WriteLine(
            "lp user PSOwner permission unset protectionstones.admin"
        )
        $server.StandardInput.WriteLine("stop")
        if (-not $server.WaitForExit(60000)) {
            $server.Kill($true)
            throw "$Lane did not stop after integration flow"
        }
    }
    if ($stdout -and $stderr) {
        ($stdout.Result + [Environment]::NewLine + $stderr.Result) |
            Set-Content -LiteralPath (
                Join-Path $serverRoot "integration-console.log"
            ) -Encoding utf8
    }
    [System.IO.File]::WriteAllBytes($configPath, $configBytes)
    [System.IO.File]::WriteAllBytes($blockPath, $blockBytes)
}

$configRestoredHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $configPath).Hash
$blockRestoredHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $blockPath).Hash
if ($configRestoredHash -ne $configOriginalHash) {
    throw "$Lane config.toml was not restored byte-for-byte"
}
if ($blockRestoredHash -ne $blockOriginalHash) {
    throw "$Lane block1.toml was not restored byte-for-byte"
}
if (-not $flowSucceeded) {
    throw "$Lane integration flow did not complete"
}

$log = Get-Content -Raw -LiteralPath $logPath
$requiredPatterns = @(
    "\[Vault\].*Enabling Vault",
    "\[PlaceholderAPI\].*Enabling PlaceholderAPI",
    "Successfully registered internal expansion: protectionstones",
    "\[ProtectionStones\].*LuckPerms support enabled!",
    "\[ProtectionStonesIntegrationProbe\].*Enabling"
)
foreach ($pattern in $requiredPatterns) {
    if ($log -notmatch $pattern) {
        throw "$Lane integration log is missing: $pattern"
    }
}

$fatalPatterns = @(
    "Error occurred while enabling ProtectionStones",
    "NoClassDefFoundError",
    "NoSuchMethodError",
    "LinkageError",
    "IllegalStateException:.*thread",
    "TickThread.*failed",
    "thread violation",
    "ProtectionStonesIntegrationProbe.*Exception"
)
foreach ($pattern in $fatalPatterns) {
    if ($log -match $pattern) {
        throw "$Lane integration log contains fatal evidence: $pattern"
    }
}

Copy-Item -LiteralPath $logPath -Destination (
    Join-Path $serverRoot "logs/integration-pass.log"
) -Force

Write-Host (
    "PASS: $Lane integrations; candidate=$installedCandidateHash; " +
    "probe=$probeHash; config=$configRestoredHash; block=$blockRestoredHash"
)
