param(
    [Parameter(Mandatory = $true)]
    [string] $Lane,
    [Parameter(Mandatory = $true)]
    [string] $JavaExe,
    [Parameter(Mandatory = $true)]
    [int] $Port,
    [Parameter(Mandatory = $true)]
    [int] $BaseX,
    [int] $BaseZ = 9000,
    [Parameter(Mandatory = $true)]
    [string] $ExpectedCandidateSha256,
    [string] $NodeExe = "node"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$workspaceRoot = Split-Path $repoRoot -Parent
$serverRoot = Join-Path $workspaceRoot "local-servers/$Lane"
$manifestPath = Join-Path $serverRoot "lane-manifest.json"
$nodeScript = Join-Path $PSScriptRoot "admin-domain-flow.mjs"
$suffix = "{0}{1}" -f ($Port - 25500), ($BaseX % 1000)
$adminName = "AAdmin$suffix"
$targetName = "ATarget$suffix"
$guestName = "AGuest$suffix"

foreach ($path in @($JavaExe, $manifestPath, $nodeScript)) {
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
if ($candidate.sha256 -ne $ExpectedCandidateSha256) {
    throw "Lane candidate hash $($candidate.sha256) does not match $ExpectedCandidateSha256"
}

function Invoke-AdminDomainPhase {
    param([ValidateSet("create", "verify")][string] $Phase)

    $logPath = Join-Path $serverRoot "logs/latest.log"
    if (Test-Path -LiteralPath $logPath -PathType Leaf) {
        $previous = "admin-domain-$Phase-previous-{0}.log" -f (
            Get-Date -Format "yyyyMMdd-HHmmss"
        )
        Move-Item -LiteralPath $logPath -Destination (
            Join-Path $serverRoot "logs/$previous"
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
        throw "Failed to start $Lane for $Phase"
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
                if ($log -match 'Done \(') {
                    $ready = $true
                    break
                }
            }
            Start-Sleep -Seconds 1
        }
        if (-not $ready) {
            throw "$Lane did not reach ready state for $Phase"
        }

        $server.StandardInput.WriteLine("op $adminName")
        $server.StandardInput.WriteLine("deop $targetName")
        $server.StandardInput.WriteLine("deop $guestName")
        Start-Sleep -Seconds 1

        $botOutput = Join-Path $serverRoot "admin-domain-$Phase-bot.log"
        & $NodeExe $nodeScript $Phase $Port $adminName $targetName $guestName `
            $BaseX $BaseZ 180000 *>&1 | Tee-Object -FilePath $botOutput
        if ($LASTEXITCODE -ne 0) {
            throw "$Lane $Phase admin domain flow failed with exit $LASTEXITCODE"
        }
        $phaseSucceeded = $true
    } finally {
        if (-not $server.HasExited) {
            $server.StandardInput.WriteLine("stop")
            if (-not $server.WaitForExit(60000)) {
                $server.Kill($true)
                throw "$Lane did not stop after $Phase"
            }
        }
        ($stdout.Result + [Environment]::NewLine + $stderr.Result) |
            Set-Content -LiteralPath (
                Join-Path $serverRoot "admin-domain-$Phase-console.log"
            ) -Encoding utf8
    }

    if ($phaseSucceeded) {
        Copy-Item -LiteralPath $logPath -Destination (
            Join-Path $serverRoot "logs/admin-domain-$Phase-pass.log"
        ) -Force
    }
}

Invoke-AdminDomainPhase -Phase create
Invoke-AdminDomainPhase -Phase verify

$fatalPatterns = @(
    'Error occurred while enabling ProtectionStones',
    'NoClassDefFoundError',
    'NoSuchMethodError',
    'LinkageError',
    'IllegalStateException:.*thread',
    'TickThread.*failed',
    'thread violation',
    'Could not complete global admin',
    'Could not persist admin'
)
foreach ($phase in @("create", "verify")) {
    $log = Get-Content -Raw -LiteralPath (
        Join-Path $serverRoot "logs/admin-domain-$phase-pass.log"
    )
    foreach ($pattern in $fatalPatterns) {
        if ($log -match $pattern) {
            throw "$Lane $phase log contains fatal evidence: $pattern"
        }
    }
}

Write-Host "PASS: $Lane completed global admin domain removal and persistence flows."
