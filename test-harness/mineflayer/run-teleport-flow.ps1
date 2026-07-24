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
$nodeScript = Join-Path $PSScriptRoot "teleport-flow.mjs"
$blockConfig = Join-Path $serverRoot "plugins/ProtectionStones/blocks/block1.toml"
$logPath = Join-Path $serverRoot "logs/latest.log"
$luckPerms = Get-ChildItem -LiteralPath (Join-Path $serverRoot "plugins") -File |
    Where-Object Name -Like "LuckPerms*.jar" |
    Select-Object -First 1
$userCachePath = Join-Path $serverRoot "usercache.json"

foreach ($path in @($JavaExe, $manifestPath, $nodeScript, $blockConfig, $userCachePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file not found: $path"
    }
}
if (-not $luckPerms) {
    throw "LuckPerms is required to deny protectionstones.tp.bypasswait explicitly."
}
if (-not (Get-Command $NodeExe -ErrorAction SilentlyContinue)) {
    throw "Node executable not found: $NodeExe"
}
$ownerEntry = (Get-Content -Raw -LiteralPath $userCachePath | ConvertFrom-Json) |
    Where-Object name -EQ "PSOwner" |
    Select-Object -First 1
if (-not $ownerEntry) {
    throw "PSOwner must join the isolated lane once before running this test."
}
$ownerUuid = $ownerEntry.uuid

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
$originalConfig = $strictUtf8.GetString($originalConfigBytes)
$testConfig = $originalConfig -replace 'tp_waiting_seconds\s*=\s*0', 'tp_waiting_seconds = 2'
if ($testConfig -eq $originalConfig) {
    throw "Could not set tp_waiting_seconds to 2 in $blockConfig"
}
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

if (Test-Path -LiteralPath $logPath -PathType Leaf) {
    $previous = "teleport-previous-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss")
    Move-Item -LiteralPath $logPath -Destination (Join-Path $serverRoot "logs/$previous")
}
[System.IO.File]::WriteAllText($blockConfig, $testConfig, $utf8NoBom)

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
            if ($log -match 'Done \(' -and $log -match '\[LuckPerms\].*enabled') {
                $ready = $true
                break
            }
        }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) {
        throw "$Lane did not reach ready state with LuckPerms"
    }

    $server.StandardInput.WriteLine("op PSOwner")
    $server.StandardInput.WriteLine(
        "lp user $ownerUuid permission set protectionstones.tp.bypasswait false"
    )
    Start-Sleep -Seconds 2

    $botOutput = Join-Path $serverRoot "teleport-bot.log"
    & $NodeExe $nodeScript $Port PSOwner $BaseX $BaseZ 90000 *>&1 |
        Tee-Object -FilePath $botOutput
    if ($LASTEXITCODE -ne 0) {
        throw "$Lane teleport bot flow failed with exit $LASTEXITCODE"
    }
    $flowSucceeded = $true
} finally {
    if ($server -and -not $server.HasExited) {
        $server.StandardInput.WriteLine(
            "lp user $ownerUuid permission unset protectionstones.tp.bypasswait"
        )
        Start-Sleep -Milliseconds 500
        $server.StandardInput.WriteLine("stop")
        if (-not $server.WaitForExit(60000)) {
            $server.Kill($true)
            throw "$Lane did not stop after teleport flow"
        }
    }
    [System.IO.File]::WriteAllBytes($blockConfig, $originalConfigBytes)
    if ($stdout -and $stderr) {
        ($stdout.Result + [Environment]::NewLine + $stderr.Result) |
            Set-Content -LiteralPath (Join-Path $serverRoot "teleport-console.log") -Encoding utf8
    }
}

if ($flowSucceeded) {
    Copy-Item -LiteralPath $logPath -Destination (
        Join-Path $serverRoot "logs/teleport-pass.log"
    ) -Force
}

$log = Get-Content -Raw -LiteralPath (Join-Path $serverRoot "logs/teleport-pass.log")
$fatalPatterns = @(
    'Error occurred while enabling ProtectionStones',
    'NoClassDefFoundError',
    'NoSuchMethodError',
    'LinkageError',
    'IllegalStateException:.*thread',
    'TickThread.*failed',
    'thread violation'
)
foreach ($pattern in $fatalPatterns) {
    if ($log -match $pattern) {
        throw "$Lane teleport log contains fatal evidence: $pattern"
    }
}

Write-Host "PASS: $Lane completed delayed and movement-cancelled teleport flows."
