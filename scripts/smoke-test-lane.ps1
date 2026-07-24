param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        "purpur-1.21.10-protectionstones-smoke",
        "purpur-26.2-protectionstones-smoke",
        "folia-26.2-protectionstones-smoke"
    )]
    [string] $Lane,
    [int] $TimeoutSeconds = 360
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $repoRoot
$serverRoot = Join-Path $workspaceRoot "local-servers/$Lane"
$manifestPath = Join-Path $serverRoot "lane-manifest.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Lane is not provisioned: $Lane"
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$javaExe = if ($manifest.java -eq 25) {
    "C:\Java\temurin-jdk-25\bin\java.exe"
} else {
    (Get-Command java).Source
}
if (-not (Test-Path -LiteralPath $javaExe -PathType Leaf)) {
    throw "Java $($manifest.java) executable not found: $javaExe"
}

$serverJar = Join-Path $serverRoot "server.jar"
$logPath = Join-Path $serverRoot "logs/latest.log"
$consolePath = Join-Path $serverRoot "smoke-console.log"
if (Test-Path -LiteralPath $logPath -PathType Leaf) {
    $archiveName = "smoke-previous-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss")
    Move-Item -LiteralPath $logPath -Destination (Join-Path (Split-Path -Parent $logPath) $archiveName)
}

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $javaExe
$startInfo.WorkingDirectory = $serverRoot
$startInfo.Arguments = "-Xms1G -Xmx2G -jar `"$serverJar`" --nogui"
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
if (-not $process.Start()) {
    throw "Failed to start $Lane"
}

$stdout = $process.StandardOutput.ReadToEndAsync()
$stderr = $process.StandardError.ReadToEndAsync()
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$started = $false
$reloadCompleted = $false

while (-not $process.HasExited -and (Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $logPath) {
        $log = Get-Content -Raw -LiteralPath $logPath
        if ($log -match 'Done \(') {
            $started = $true
            break
        }
    }
    Start-Sleep -Seconds 2
}

if ($started) {
    $process.StandardInput.WriteLine("version")
    $process.StandardInput.WriteLine("plugins")
    $process.StandardInput.WriteLine("ps reload")

    $reloadDeadline = (Get-Date).AddSeconds(30)
    while (-not $process.HasExited -and (Get-Date) -lt $reloadDeadline) {
        if (Test-Path -LiteralPath $logPath) {
            $log = Get-Content -Raw -LiteralPath $logPath
            if ($log -match 'Completed config reload!') {
                $reloadCompleted = $true
                break
            }
        }
        Start-Sleep -Seconds 1
    }
    $process.StandardInput.WriteLine("stop")
} elseif (-not $process.HasExited) {
    $process.StandardInput.WriteLine("stop")
}

if (-not $process.WaitForExit(60000)) {
    $process.Kill($true)
    throw "$Lane did not stop within 60 seconds"
}

($stdout.Result + [Environment]::NewLine + $stderr.Result) |
    Set-Content -LiteralPath $consolePath -Encoding utf8

if (-not $started) {
    throw "$Lane did not reach the ready state within $TimeoutSeconds seconds"
}
if (-not $reloadCompleted) {
    throw "$Lane did not complete /ps reload within 30 seconds"
}

$log = Get-Content -Raw -LiteralPath $logPath
$required = @(
    '\[WorldEdit\].*Enabling WorldEdit',
    '\[WorldGuard\].*Enabling WorldGuard',
    '\[ProtectionStones\].*Enabling ProtectionStones',
    'ProtectionStones has successfully started!',
    'Completed config reload!'
)
foreach ($pattern in $required) {
    if ($log -notmatch $pattern) {
        throw "$Lane is missing required log evidence: $pattern"
    }
}

$fatalPatterns = @(
    'Unsupported API version',
    'Could not load.*ProtectionStones',
    'Error occurred while enabling ProtectionStones',
    'NoClassDefFoundError',
    'IllegalStateException:.*thread',
    'TickThread.*failed'
)
foreach ($pattern in $fatalPatterns) {
    if ($log -match $pattern) {
        throw "$Lane contains fatal log evidence: $pattern"
    }
}

Write-Host "PASS: $Lane enabled, reloaded, and stopped cleanly."
