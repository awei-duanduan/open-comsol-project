param(
    [string]$ConfigPath,
    [string]$ServerExe,
    [string]$GuiExe,
    [string]$ServerHost = "localhost",
    [int]$ServerPort = 2038,
    [int]$StartupTimeoutSeconds = 120,
    [int]$ProbeTimeoutSeconds = 45,
    [switch]$AcceptDefaults,
    [switch]$SkipCheck,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Get-SkillRoot {
    return (Split-Path -Parent $PSScriptRoot)
}

function Find-ComsolInstall {
    $candidates = New-Object System.Collections.Generic.List[string]

    $roots = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)}
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    foreach ($root in $roots) {
        Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^COMSOL' } |
            ForEach-Object { [void]$candidates.Add($_.FullName) }
    }

    Get-PSDrive -PSProvider FileSystem |
        ForEach-Object {
            $driveRoot = $_.Root
            foreach ($name in @("COMSOL", "COMSOL62", "COMSOL6.2", "COMSOL Multiphysics")) {
                $path = Join-Path $driveRoot $name
                if (Test-Path -LiteralPath $path) {
                    [void]$candidates.Add($path)
                }
            }
        }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        $server = Get-ChildItem -LiteralPath $candidate -Recurse -Filter "comsolmphserver.exe" -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        if (-not $server) {
            continue
        }

        $binDir = Split-Path -Parent $server
        $gui = Join-Path $binDir "comsol.exe"
        if (Test-Path -LiteralPath $gui) {
            return @{
                ServerExe = $server
                GuiExe = $gui
            }
        }
    }

    return $null
}

function Read-PathWithDefault {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [string]$DefaultValue
    )

    if ($DefaultValue) {
        if ($AcceptDefaults) {
            return $DefaultValue
        }

        $answer = Read-Host "$Prompt [$DefaultValue]"
        if (-not $answer) {
            return $DefaultValue
        }
        return $answer
    }

    return (Read-Host $Prompt)
}

function Require-ExistingFile {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label does not exist: $Path"
    }
}

if (-not $ConfigPath) {
    $ConfigPath = Join-Path (Get-SkillRoot) "config.env"
}

if ((Test-Path -LiteralPath $ConfigPath) -and -not $Force) {
    Write-Host "Config already exists: $ConfigPath"
    Write-Host "Use -Force to overwrite it."
    exit 0
}

$detected = Find-ComsolInstall
if ($detected) {
    Write-Host "Detected COMSOL executables:"
    Write-Host "  Server: $($detected.ServerExe)"
    Write-Host "  GUI:    $($detected.GuiExe)"
}
else {
    Write-Host "Could not auto-detect COMSOL. Please enter the executable paths."
}

if (-not $ServerExe) {
    $ServerExe = Read-PathWithDefault -Prompt "Path to comsolmphserver.exe" -DefaultValue $detected.ServerExe
}
if (-not $GuiExe) {
    $GuiExe = Read-PathWithDefault -Prompt "Path to comsol.exe" -DefaultValue $detected.GuiExe
}

Require-ExistingFile -Label "comsolmphserver.exe" -Path $ServerExe
Require-ExistingFile -Label "comsol.exe" -Path $GuiExe

$ServerHost = Read-PathWithDefault -Prompt "Server host" -DefaultValue $ServerHost
$ServerPort = [int](Read-PathWithDefault -Prompt "Server port" -DefaultValue ([string]$ServerPort))
$StartupTimeoutSeconds = [int](Read-PathWithDefault -Prompt "Startup timeout seconds" -DefaultValue ([string]$StartupTimeoutSeconds))
$ProbeTimeoutSeconds = [int](Read-PathWithDefault -Prompt "Python probe timeout seconds" -DefaultValue ([string]$ProbeTimeoutSeconds))

$configDir = Split-Path -Parent $ConfigPath
if ($configDir -and -not (Test-Path -LiteralPath $configDir)) {
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
}

$serverArgs = "-port $ServerPort"
$lines = @(
    "set `"SERVER_HOST=$ServerHost`"",
    "set `"SERVER_PORT=$ServerPort`"",
    "set `"SERVER_ARGS=$serverArgs`"",
    "set `"STARTUP_TIMEOUT_SECONDS=$StartupTimeoutSeconds`"",
    "set `"PROBE_TIMEOUT_SECONDS=$ProbeTimeoutSeconds`"",
    "set `"SERVER_BAT=$ServerExe`"",
    "set `"COMSOL_GUI_EXE=$GuiExe`"",
    "set `"COMSOL_GUI_LNK=`""
)

Set-Content -LiteralPath $ConfigPath -Value $lines -Encoding ASCII
Write-Host "Wrote COMSOL skill config: $ConfigPath"

if (-not $SkipCheck) {
    $checkScript = Join-Path $PSScriptRoot "Test-ComsolEnvironment.ps1"
    Write-Host ""
    Write-Host "Running environment check..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File $checkScript -ConfigPath $ConfigPath
    if ($LASTEXITCODE -ne 0) {
        throw "Environment check failed. Re-run this initializer with -Force after correcting the paths."
    }
}
