#Requires -Version 5.1
<#
    Session doctor: check the preconditions a .NET solution's test suite assumes,
    at the start of a session rather than three minutes into a run.

    Nothing about any particular repository is written down here. The target
    framework, whether a container runtime is needed at all, and which
    environment keys are expected are all discovered, and
    session-doctor.config.json overrides the discovery when it guesses wrong.

    It never blocks. A hook that traps a session is worse than one that misses,
    and a broken environment is a fact to be told about, not a door to be shut.
    Exit code is always 0; findings go to stdout, which a SessionStart hook adds
    to the session's context.

    Run it by hand with -Report to see every check and its verdict.
#>

[CmdletBinding()]
param(
    # Print every check and its verdict. Without it, the script is silent unless
    # something failed -- which is what makes it bearable on every session start.
    [switch] $Report,

    # Where to look. The hook passes this from the payload; a manual run defaults
    # to the current directory.
    [string] $RepoRoot
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Every native command goes through here. Under $ErrorActionPreference = 'Stop',
# redirecting a native executable's stderr wraps each line in an ErrorRecord and
# throws NativeCommandError, so a check would die instead of reporting a failure.
function Invoke-Native([string] $command, [string[]] $arguments) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $command @arguments 2>&1 | ForEach-Object { $_.ToString() })
        $code = $LASTEXITCODE
    }
    catch {
        return [PSCustomObject] @{ Output = @($_.Exception.Message); ExitCode = 1 }
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

# ---------------------------------------------------------------- findings ---

$checks = New-Object System.Collections.ArrayList

function Add-Check([string] $name, [bool] $ok, [string] $detail) {
    [void] $checks.Add([PSCustomObject] @{ Name = $name; Ok = $ok; Detail = $detail })
}

# ---------------------------------------------------------------- payload ----

if (-not $RepoRoot) {
    $raw = ''
    if (-not $Report) {
        # Only the hook has a payload on stdin. Reading it in -Report mode from an
        # interactive console would block forever.
        $raw = [Console]::In.ReadToEnd()
    }
    if ($raw -and $raw.Trim()) {
        try {
            $payload = $raw | ConvertFrom-Json
            $RepoRoot = Get-Prop $payload 'cwd'
        }
        catch { $RepoRoot = $null }
    }
}
if (-not $RepoRoot) { $RepoRoot = (Get-Location).Path }
if (-not (Test-Path -LiteralPath $RepoRoot)) { exit 0 }
Set-Location -LiteralPath $RepoRoot
$RepoRoot = (Get-Location).Path

# -------------------------------------------------------------- discovery ----

# git first: it answers in milliseconds and already skips bin, obj and
# node_modules. The depth-limited walk stays as the fallback for a project not
# yet tracked.
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

$projectFiles = @(Get-ProjectFiles $RepoRoot)
if ($projectFiles.Count -eq 0) { exit 0 }   # not a .NET repository: say nothing

# The build files carry the target framework as often as the projects do, and in
# a repository with Directory.Build.props they are the only place it appears.
$buildFiles = @(Get-ChildItem -LiteralPath $RepoRoot -File -Filter '*.props' -ErrorAction SilentlyContinue)

$needsContainer = $false
foreach ($project in $projectFiles) {
    $content = Get-Content -LiteralPath $project.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) { continue }
    if ($content -match 'Testcontainers') { $needsContainer = $true }
}

$frameworks = @()
foreach ($file in @($projectFiles + $buildFiles)) {
    $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) { continue }
    foreach ($match in [regex]::Matches($content, '<TargetFrameworks?>([^<]+)</TargetFrameworks?>')) {
        foreach ($value in ($match.Groups[1].Value -split ';')) {
            $value = $value.Trim()
            if ($value -match '^net(\d+)\.\d+$') { $frameworks += $value }
        }
    }
}
$frameworks = @($frameworks | Sort-Object -Unique)

# ---------------------------------------------------------------- override ---

$runtimeCommand = 'docker'
$envExample = '.env.example'
$envFile = '.env'
$requiredFiles = @()
$disabled = @()

$configFile = Join-Path $RepoRoot '.claude\hooks\session-doctor.config.json'
if (Test-Path -LiteralPath $configFile) {
    try {
        $config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
        $configured = Get-Prop $config 'containerRuntime'
        if ($configured) { $runtimeCommand = $configured }
        $configured = Get-Prop $config 'envExample'
        if ($configured) { $envExample = $configured }
        $configured = Get-Prop $config 'envFile'
        if ($configured) { $envFile = $configured }
        $configured = Get-Prop $config 'requiredFiles'
        if ($configured) { $requiredFiles = @($configured) }
        $configured = Get-Prop $config 'skip'
        if ($configured) { $disabled = @($configured) }
    }
    catch {
        Add-Check 'config' $false 'session-doctor.config.json could not be read; using discovery.'
    }
}

function Test-Enabled([string] $name) {
    return -not ($disabled -contains $name)
}

# ------------------------------------------------------------------- 1. sdk --

if ((Test-Enabled 'sdk') -and $frameworks.Count -gt 0) {
    $sdks = Invoke-Native 'dotnet' @('--list-sdks')
    if ($sdks.ExitCode -ne 0) {
        Add-Check 'sdk' $false "the projects target $($frameworks -join ', ') and 'dotnet' is not on PATH."
    }
    else {
        $majors = @()
        foreach ($line in $sdks.Output) {
            if ($line -match '^(\d+)\.') { $majors += [int] $matches[1] }
        }
        $missing = @()
        foreach ($framework in $frameworks) {
            if ($framework -match '^net(\d+)\.') {
                $wanted = [int] $matches[1]
                if ($majors -notcontains $wanted) { $missing += $framework }
            }
        }
        if ($missing.Count -gt 0) {
            Add-Check 'sdk' $false ("no SDK for $($missing -join ', '); installed majors: " +
                "$(@($majors | Sort-Object -Unique) -join ', '). The build will fail on restore.")
        }
        else {
            Add-Check 'sdk' $true "$($frameworks -join ', ') covered by an installed SDK."
        }
    }
}

# ------------------------------------------------------------- 2. container --

if ((Test-Enabled 'container') -and $needsContainer -and $runtimeCommand -ne 'none') {
    if (-not (Get-Command $runtimeCommand -ErrorAction SilentlyContinue)) {
        Add-Check 'container' $false ("a test project references Testcontainers and '$runtimeCommand' " +
            'is not on PATH. Those suites cannot run.')
    }
    else {
        # --format keeps this to one round trip and fails fast when the daemon is
        # down, where 'info' prints a page before it gets to the point.
        $version = Invoke-Native $runtimeCommand @('version', '--format', '{{.Server.Version}}')
        if ($version.ExitCode -ne 0) {
            Add-Check 'container' $false ("a test project references Testcontainers and the " +
                "$runtimeCommand daemon is not responding. Start it before running the full suite.")
        }
        else {
            $reported = 'version not reported'
            if ($version.Output.Count -gt 0) { $reported = "server $($version.Output[0])" }
            Add-Check 'container' $true "$runtimeCommand daemon responding ($reported)."
        }
    }
}
elseif ((Test-Enabled 'container') -and -not $needsContainer -and $Report) {
    Add-Check 'container' $true 'no test project references Testcontainers; not required.'
}

# ------------------------------------------------------------------- 3. env --

function Get-EnvKeys([string] $path) {
    $keys = @()
    foreach ($line in @(Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*#') { continue }
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=') { $keys += $matches[1] }
    }
    return $keys
}

$examplePath = Join-Path $RepoRoot $envExample
if ((Test-Enabled 'env') -and (Test-Path -LiteralPath $examplePath)) {
    $actualPath = Join-Path $RepoRoot $envFile
    if (-not (Test-Path -LiteralPath $actualPath)) {
        Add-Check 'env' $false "$envExample exists and $envFile does not. Copy it and fill in the values."
    }
    else {
        $expected = @(Get-EnvKeys $examplePath)
        $actual = @(Get-EnvKeys $actualPath)
        $missing = @($expected | Where-Object { $actual -notcontains $_ })
        if ($missing.Count -gt 0) {
            Add-Check 'env' $false "$envFile is missing $($missing.Count) key(s) $envExample declares: $($missing -join ', ')."
        }
        else {
            Add-Check 'env' $true "$envFile carries every key $envExample declares."
        }
    }
}

# -------------------------------------------------------- 4. required files --

if ($requiredFiles.Count -gt 0) {
    $absent = @($requiredFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $RepoRoot $_)) })
    if ($absent.Count -gt 0) {
        Add-Check 'files' $false "missing, and session-doctor.config.json requires them: $($absent -join ', ')."
    }
    else {
        Add-Check 'files' $true "every file session-doctor.config.json requires is present."
    }
}

# ---------------------------------------------------------------- report -----

$failed = @($checks | Where-Object { -not $_.Ok })

if ($Report) {
    Write-Output "session-doctor: $RepoRoot"
    foreach ($check in $checks) {
        $mark = 'FAIL'
        if ($check.Ok) { $mark = ' ok ' }
        Write-Output ("  [{0}] {1,-10} {2}" -f $mark, $check.Name, $check.Detail)
    }
    if ($checks.Count -eq 0) { Write-Output '  nothing to check.' }
    exit 0
}

if ($failed.Count -eq 0) { exit 0 }

Write-Output 'session-doctor found the environment incomplete before any command was run:'
foreach ($check in $failed) {
    Write-Output "  - $($check.Detail)"
}
Write-Output 'Say so before running a suite that depends on it, rather than reporting its failure as a code defect.'
exit 0
