#Requires -Version 5.1
<#
    Stop gate: format what changed, then refuse to end the turn on a broken
    build or a failing fast test suite.

    Nothing about any particular repository is written down here. The solution,
    the test projects and which of them need Docker are all discovered, and
    stop-gate.config.json overrides the discovery when it guesses wrong.

    Exit codes: 0 lets the turn end, 2 blocks it and shows stderr to the model.
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-Note([string] $message) {
    [Console]::Error.WriteLine($message)
}

# Every native command goes through here. Under $ErrorActionPreference = 'Stop',
# redirecting a native executable's stderr wraps each line in an ErrorRecord and
# throws NativeCommandError -- so the script died with exit 1 (which does not
# block) at exactly the moment a failing test should have blocked the turn.
function Invoke-Native([string] $command, [string[]] $arguments) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $command @arguments 2>&1 | ForEach-Object { $_.ToString() })
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
    return [PSCustomObject] @{ Output = $output; ExitCode = $code }
}

function Get-Prop($object, [string] $name) {
    if ($null -eq $object) { return $null }
    $property = $object.PSObject.Properties[$name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

# ---------------------------------------------------------------- payload ----

$raw = [Console]::In.ReadToEnd()
$payload = $null
if ($raw -and $raw.Trim()) {
    try { $payload = $raw | ConvertFrom-Json } catch { $payload = $null }
}

$repoRoot = Get-Prop $payload 'cwd'
if (-not $repoRoot) { $repoRoot = (Get-Location).Path }
if (-not (Test-Path -LiteralPath $repoRoot)) { exit 0 }
Set-Location -LiteralPath $repoRoot
$repoRoot = (Get-Location).Path

$sessionId = Get-Prop $payload 'session_id'
if (-not $sessionId) { $sessionId = 'no-session' }
$sessionId = ($sessionId -replace '[^A-Za-z0-9_-]', '_')

$stateDir = Join-Path $env:TEMP 'claude-stop-gate'
if (-not (Test-Path -LiteralPath $stateDir)) {
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
}

function Get-RepoKey([string] $path) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($path.ToLowerInvariant())
    $hash = $md5.ComputeHash($bytes)
    $md5.Dispose()
    return ([System.BitConverter]::ToString($hash) -replace '-', '').Substring(0, 16)
}

$repoKey = Get-RepoKey $repoRoot

# ------------------------------------------------------------ block counter --
# Three consecutive blocks is a loop, not a gate. The third one warns and lets
# the turn end: a hook that traps the session is worse than one that misses.

$counterFile = Join-Path $stateDir "$sessionId.blocks"

function Get-BlockCount {
    if (-not (Test-Path -LiteralPath $counterFile)) { return 0 }
    $text = Get-Content -LiteralPath $counterFile -Raw -ErrorAction SilentlyContinue
    if (-not $text) { return 0 }
    $value = 0
    if ([int]::TryParse($text.Trim(), [ref] $value)) { return $value }
    return 0
}

function Set-BlockCount([int] $value) {
    Set-Content -LiteralPath $counterFile -Value $value -Encoding ASCII
}

function Stop-Turn([string] $reason) {
    $count = Get-BlockCount
    if ($count -ge 2) {
        Set-BlockCount 0
        Write-Note "stop-gate: $reason"
        Write-Note 'stop-gate: third consecutive block, letting the turn end anyway. Fix this before the next one.'
        exit 0
    }
    Set-BlockCount ($count + 1)
    Write-Note "stop-gate: $reason"
    exit 2
}

function Pass-Turn {
    Set-BlockCount 0
    exit 0
}

# -------------------------------------------------------------- discovery ----

# git first: it answers in milliseconds and already skips bin, obj and
# node_modules, whereas a recursive walk of a repository with node_modules costs
# five seconds per turn to conclude that this is not a .NET repository at all.
# The walk stays as the fallback, depth-limited, for a project not yet tracked.
function Get-ProjectFiles([string] $root) {
    $tracked = Invoke-Native 'git' @('ls-files', '--cached', '--others', '--exclude-standard', '*.csproj')
    if ($tracked.ExitCode -eq 0 -and $tracked.Output.Count -gt 0) {
        return @($tracked.Output |
            Where-Object { $_ -and $_ -notmatch '[\\/](bin|obj)[\\/]' } |
            ForEach-Object { Get-Item -LiteralPath (Join-Path $root $_) -ErrorAction SilentlyContinue })
    }
    return @(Get-ChildItem -LiteralPath $root -Recurse -Depth 3 -Filter '*.csproj' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/](bin|obj|node_modules)[\\/]' })
}

function Get-Fingerprint($projectFiles) {
    if (-not $projectFiles -or $projectFiles.Count -eq 0) { return '0|0' }
    # Measure-Object -Maximum returns a double, which serialises as 6.39E+17 and
    # compares equal across edits it should have caught. The loop keeps it a long.
    [long] $ticks = 0
    foreach ($file in $projectFiles) {
        if ($file.LastWriteTimeUtc.Ticks -gt $ticks) { $ticks = $file.LastWriteTimeUtc.Ticks }
    }
    return '{0}|{1}' -f $projectFiles.Count, $ticks
}

function New-Discovery([string] $root, $projectFiles, [string] $fingerprint) {
    $solutions = @(Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq '.slnx' -or $_.Extension -eq '.sln' })

    $solution = ''
    if ($solutions.Count -eq 1) { $solution = $solutions[0].FullName }

    $fast = @()
    $docker = @()
    foreach ($project in $projectFiles) {
        $content = Get-Content -LiteralPath $project.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }
        if ($content -notmatch 'Microsoft\.NET\.Test\.Sdk') { continue }
        if ($content -match 'Testcontainers') { $docker += $project.FullName }
        else { $fast += $project.FullName }
    }

    return [PSCustomObject] @{
        fingerprint        = $fingerprint
        solution           = $solution
        solutionCount      = $solutions.Count
        fastTestProjects   = $fast
        dockerTestProjects = $docker
    }
}

$projectFiles = @(Get-ProjectFiles $repoRoot)
if ($projectFiles.Count -eq 0) { exit 0 }   # not a .NET repository: say nothing

$fingerprint = Get-Fingerprint $projectFiles
$cacheFile = Join-Path $stateDir "$repoKey.discovery.json"
$discovery = $null
if (Test-Path -LiteralPath $cacheFile) {
    try {
        $cached = Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json
        if ((Get-Prop $cached 'fingerprint') -eq $fingerprint) { $discovery = $cached }
    } catch { $discovery = $null }
}
if ($null -eq $discovery) {
    $discovery = New-Discovery $repoRoot $projectFiles $fingerprint
    $discovery | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $cacheFile -Encoding UTF8
}

# ---------------------------------------------------------------- override ---

$solution = [string] (Get-Prop $discovery 'solution')
$fastTestProjects = @(Get-Prop $discovery 'fastTestProjects')
$formatMode = 'auto'
$blockOn = @('build', 'fastTests')

$configFile = Join-Path $repoRoot '.claude\hooks\stop-gate.config.json'
if (Test-Path -LiteralPath $configFile) {
    try {
        $config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
        $configured = Get-Prop $config 'solution'
        if ($configured) { $solution = (Join-Path $repoRoot $configured) }
        $configured = Get-Prop $config 'fastTestProjects'
        if ($configured) { $fastTestProjects = @($configured | ForEach-Object { Join-Path $repoRoot $_ }) }
        $configured = Get-Prop $config 'formatMode'
        if ($configured) { $formatMode = $configured }
        $configured = Get-Prop $config 'blockOn'
        if ($null -ne $configured) { $blockOn = @($configured) }
    } catch {
        Write-Note 'stop-gate: stop-gate.config.json could not be read, using discovery.'
    }
}

$buildTarget = $solution
if (-not $buildTarget) {
    $count = Get-Prop $discovery 'solutionCount'
    Write-Note "stop-gate: $count solution files in the root, building the working directory instead."
}

# -------------------------------------------------------- 1. format changed --

function Get-ChangedCSharpFiles {
    $status = Invoke-Native 'git' @('status', '--porcelain', '--', '*.cs')
    if ($status.ExitCode -ne 0) { return @() }
    $files = @()
    foreach ($line in $status.Output) {
        if ($line.Length -lt 4) { continue }
        $status = $line.Substring(0, 2)
        if ($status -eq ' D' -or $status -eq 'D ') { continue }
        $path = $line.Substring(3).Trim()
        if ($path -match ' -> ') { $path = ($path -split ' -> ')[-1] }
        $path = $path.Trim('"')
        if ($path -match '[\\/](bin|obj)[\\/]') { continue }
        if (Test-Path -LiteralPath $path) { $files += $path }
    }
    return $files
}

function Get-OwningProject([string] $file) {
    $directory = Split-Path -Parent (Resolve-Path -LiteralPath $file).Path
    while ($directory -and $directory.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
        $found = @(Get-ChildItem -LiteralPath $directory -Filter '*.csproj' -File -ErrorAction SilentlyContinue)
        if ($found.Count -gt 0) { return $found[0].FullName }
        $directory = Split-Path -Parent $directory
    }
    return $null
}

$changed = @(Get-ChangedCSharpFiles)
if ($changed.Count -gt 0 -and $formatMode -ne 'off') {
    $byProject = @{}
    foreach ($file in $changed) {
        $owner = Get-OwningProject $file
        if (-not $owner) { continue }
        if (-not $byProject.ContainsKey($owner)) { $byProject[$owner] = @() }
        $byProject[$owner] += $file
    }

    if ($byProject.Count -gt 0) {
        $bySolution = $false
        if ($formatMode -eq 'solution') { $bySolution = $true }
        elseif ($formatMode -eq 'auto' -and $byProject.Count -ge 3 -and $solution) { $bySolution = $true }

        if ($bySolution -and $solution) {
            $format = Invoke-Native 'dotnet' (@('format', $solution, '--include') + $changed + @('--no-restore', '--verbosity', 'quiet'))
            if ($format.ExitCode -ne 0) { Write-Note 'stop-gate: dotnet format failed, continuing.' }
        }
        else {
            foreach ($owner in $byProject.Keys) {
                $format = Invoke-Native 'dotnet' (@('format', $owner, '--include') + $byProject[$owner] + @('--no-restore', '--verbosity', 'quiet'))
                if ($format.ExitCode -ne 0) { Write-Note "stop-gate: dotnet format failed for $(Split-Path -Leaf $owner), continuing." }
            }
        }
    }
}

# ----------------------------------------------------------------- 2. build --

$buildArguments = @('build', '--nologo', '--verbosity', 'quiet')
if ($buildTarget) { $buildArguments = @('build', $buildTarget, '--nologo', '--verbosity', 'quiet') }

$build = Invoke-Native 'dotnet' $buildArguments
if ($build.ExitCode -ne 0) {
    if ($blockOn -contains 'build') {
        $detail = (@($build.Output | Select-String -Pattern 'error|warning' | Select-Object -Unique -First 15) -join "`n")
        Stop-Turn "the build fails. Fix it before ending the turn.`n$detail"
    }
    Write-Note 'stop-gate: the build fails.'
}

# ------------------------------------------------------------ 3. fast tests --

if ($fastTestProjects.Count -eq 0) {
    Write-Note 'stop-gate: no test project without Testcontainers was found, skipping the fast suite.'
    Pass-Turn
}

foreach ($project in $fastTestProjects) {
    $test = Invoke-Native 'dotnet' @('test', $project, '--nologo', '--verbosity', 'quiet', '--no-build')
    if ($test.ExitCode -ne 0) {
        if ($blockOn -contains 'fastTests') {
            $detail = (@($test.Output | Select-String -Pattern '\[FAIL\]|error|Failed!' | Select-Object -Unique -First 15) -join "`n")
            $name = Split-Path -Leaf $project
            Stop-Turn "$name fails. Fix it before ending the turn.`n$detail"
        }
        Write-Note "stop-gate: $(Split-Path -Leaf $project) fails."
    }
}

Pass-Turn
