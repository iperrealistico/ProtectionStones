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
$nodeScript = Join-Path $PSScriptRoot "probe-flow.mjs"
$probeJar = Join-Path $repoRoot "test-harness/runtime-probe/target/ProtectionStonesRuntimeProbe.jar"
$installedProbe = Join-Path $serverRoot "plugins/ProtectionStonesRuntimeProbe.jar"
$blockConfig = Join-Path $serverRoot "plugins/ProtectionStones/blocks/block1.toml"
$logPath = Join-Path $serverRoot "logs/latest.log"

foreach ($path in @($JavaExe, $manifestPath, $nodeScript, $probeJar, $blockConfig)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file not found: $path"
    }
}
if (-not (Get-Command $NodeExe -ErrorAction SilentlyContinue)) {
    throw "Node executable not found: $NodeExe"
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$candidate = $manifest.files | Where-Object {
    $_.name -eq "ProtectionStones-2.10.6-pvc.1.jar"
}
if (-not $candidate) {
    throw "Candidate is missing from the lane manifest."
}
if ($ExpectedCandidateSha256 -and $candidate.sha256 -ne $ExpectedCandidateSha256) {
    throw "Lane candidate hash $($candidate.sha256) does not match $ExpectedCandidateSha256"
}

$originalConfigBytes = [System.IO.File]::ReadAllBytes($blockConfig)
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$originalConfig = $strictUtf8.GetString($originalConfigBytes)
$testConfig = $originalConfig `
    -replace 'enable\s*=\s*false', 'enable = true' `
    -replace "on_region_create\s*=\s*\[", "on_region_create = [`r`n        'message: PSCONFIG CREATE %region%'," `
    -replace "on_region_destroy\s*=\s*\[", "on_region_destroy = [`r`n        'message: PSCONFIG DESTROY %region%',"
if ($testConfig -eq $originalConfig) {
    throw "Could not enable configured event actions in $blockConfig"
}

Copy-Item -LiteralPath $probeJar -Destination $installedProbe -Force
[System.IO.File]::WriteAllText($blockConfig, $testConfig, $utf8NoBom)
if (Test-Path -LiteralPath $logPath -PathType Leaf) {
    $previous = "probe-previous-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss")
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
            if ($log -match 'Done \(' -and $log -match 'Enabling ProtectionStonesRuntimeProbe') {
                $ready = $true
                break
            }
        }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) {
        throw "$Lane did not reach ready state with the runtime probe"
    }

    $server.StandardInput.WriteLine("op PSOwner")
    Start-Sleep -Seconds 1

    $botOutput = Join-Path $serverRoot "probe-bot.log"
    & $NodeExe $nodeScript $Port PSOwner $BaseX $BaseZ 90000 *>&1 |
        Tee-Object -FilePath $botOutput
    if ($LASTEXITCODE -ne 0) {
        throw "$Lane probe bot flow failed with exit $LASTEXITCODE"
    }
    $flowSucceeded = $true
} finally {
    if ($server -and -not $server.HasExited) {
        $server.StandardInput.WriteLine("stop")
        if (-not $server.WaitForExit(60000)) {
            $server.Kill($true)
            throw "$Lane did not stop after probe flow"
        }
    }
    [System.IO.File]::WriteAllBytes($blockConfig, $originalConfigBytes)
    if ($stdout -and $stderr) {
        ($stdout.Result + [Environment]::NewLine + $stderr.Result) |
            Set-Content -LiteralPath (Join-Path $serverRoot "probe-console.log") -Encoding utf8
    }
}

if ($flowSucceeded) {
    Copy-Item -LiteralPath $logPath -Destination (
        Join-Path $serverRoot "logs/probe-pass.log"
    ) -Force
}

$log = Get-Content -Raw -LiteralPath (Join-Path $serverRoot "logs/probe-pass.log")
$fatalPatterns = @(
    'Error occurred while enabling ProtectionStones',
    'Error occurred while enabling ProtectionStonesRuntimeProbe',
    'NoClassDefFoundError',
    'NoSuchMethodError',
    'LinkageError',
    'IllegalStateException:.*thread',
    'TickThread.*failed',
    'thread violation'
)
foreach ($pattern in $fatalPatterns) {
    if ($log -match $pattern) {
        throw "$Lane probe log contains fatal evidence: $pattern"
    }
}

if ($log -notmatch 'PSPROBE VIEW command=true activeTasks=[1-9][0-9]*') {
    throw "$Lane probe log does not contain a successful /ps view particle-task assertion"
}

Write-Host "PASS: $Lane completed API, custom-event, configured-action, environment, and /ps view flows."
