param(
    [Parameter(Mandatory = $true)]
    [string] $BaselineJar,
    [Parameter(Mandatory = $true)]
    [string] $CandidateJar,
    [string] $PackagePrefix = "dev.espi.protectionstones."
)

$ErrorActionPreference = "Stop"

$BaselineJar = [System.IO.Path]::GetFullPath($BaselineJar)
$CandidateJar = [System.IO.Path]::GetFullPath($CandidateJar)
foreach ($path in @($BaselineJar, $CandidateJar)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "JAR not found: $path"
    }
}

$javaHome = if ($env:JAVA_HOME) {
    $env:JAVA_HOME
} else {
    Split-Path -Parent (Split-Path -Parent (Get-Command java).Source)
}
$jarExe = Join-Path $javaHome "bin/jar.exe"
$javapExe = Join-Path $javaHome "bin/javap.exe"
foreach ($tool in @($jarExe, $javapExe)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Required JDK tool not found: $tool"
    }
}

function Get-ClassNames {
    param([string] $JarPath)

    $pathPrefix = $PackagePrefix.Replace(".", "/")
    return @(& $jarExe tf $JarPath |
        Where-Object {
            $_.StartsWith($pathPrefix) -and
            $_.EndsWith(".class") -and
            -not $_.EndsWith("module-info.class")
        } |
        ForEach-Object {
            $_.Substring(0, $_.Length - 6).Replace("/", ".")
        })
}

function Get-ClassApi {
    param(
        [string] $JarPath,
        [string] $ClassName
    )

    $lines = @(& $javapExe -classpath $JarPath -protected -s $ClassName 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "javap failed for $ClassName in $JarPath`n$($lines -join [Environment]::NewLine)"
    }

    $declaration = $lines |
        ForEach-Object { $_.Trim() } |
        Where-Object {
            $_ -match '^(public|protected) .*\b(class|interface|enum|record)\b'
        } |
        Select-Object -First 1
    if (-not $declaration) {
        return $null
    }

    $members = New-Object "System.Collections.Generic.HashSet[string]"
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index].Trim()
        if ($line -notmatch '^(public|protected) ' -or
            $line -match '\b(class|interface|enum|record)\b') {
            continue
        }

        $descriptor = $null
        if ($index + 1 -lt $lines.Count) {
            $next = $lines[$index + 1].Trim()
            if ($next.StartsWith("descriptor: ")) {
                $descriptor = $next.Substring("descriptor: ".Length)
            }
        }
        if (-not $descriptor) {
            continue
        }

        if ($line.Contains("(")) {
            $beforeParameters = $line.Substring(0, $line.IndexOf("("))
            $memberName = ($beforeParameters -split '\s+')[-1]
            $kind = "method"
        } else {
            $memberName = (($line.TrimEnd(";")) -split '\s+')[-1]
            $kind = "field"
        }
        [void] $members.Add("$kind|$memberName|$descriptor")
    }

    return [pscustomobject]@{
        Name = $ClassName
        Declaration = $declaration
        Members = $members
    }
}

$candidateClasses = New-Object "System.Collections.Generic.HashSet[string]"
Get-ClassNames -JarPath $CandidateJar | ForEach-Object {
    [void] $candidateClasses.Add($_)
}

$publicClassCount = 0
$publicMemberCount = 0
$missingClasses = New-Object System.Collections.Generic.List[string]
$missingMembers = New-Object System.Collections.Generic.List[string]

foreach ($className in Get-ClassNames -JarPath $BaselineJar) {
    $baselineApi = Get-ClassApi -JarPath $BaselineJar -ClassName $className
    if (-not $baselineApi) {
        continue
    }
    $publicClassCount++

    if (-not $candidateClasses.Contains($className)) {
        $missingClasses.Add($className)
        continue
    }

    $candidateApi = Get-ClassApi -JarPath $CandidateJar -ClassName $className
    if (-not $candidateApi) {
        $missingClasses.Add("$className (no longer public/protected)")
        continue
    }

    foreach ($member in $baselineApi.Members) {
        $publicMemberCount++
        if (-not $candidateApi.Members.Contains($member)) {
            $missingMembers.Add("$className :: $member")
        }
    }
}

Write-Host "Baseline public/protected classes: $publicClassCount"
Write-Host "Baseline public/protected members: $publicMemberCount"
Write-Host "Missing classes: $($missingClasses.Count)"
Write-Host "Missing members: $($missingMembers.Count)"

if ($missingClasses.Count -gt 0 -or $missingMembers.Count -gt 0) {
    $missingClasses | ForEach-Object { Write-Host "Missing API class: $_" }
    $missingMembers | ForEach-Object { Write-Host "Missing API member: $_" }
    throw "Candidate is not binary API-compatible with the baseline."
}

Write-Host "PASS: candidate preserves the baseline public/protected JVM API."
