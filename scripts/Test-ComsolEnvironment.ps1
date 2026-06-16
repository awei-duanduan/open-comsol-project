param(
    [string]$ConfigPath,
    [string]$PythonExe = "python",
    [switch]$CheckPython,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

function Get-SkillRoot {
    return (Split-Path -Parent $PSScriptRoot)
}

function Write-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Quiet) {
        Write-Host "[$Status] $Message"
    }
}

function Read-BatEnv {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: $Path"
    }

    $envMap = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith("#")) {
            continue
        }

        if ($trimmed -match '^set\s+"([^=]+)=(.*)"\s*$') {
            $envMap[$Matches[1]] = $Matches[2]
            continue
        }

        if ($trimmed -match '^set\s+([^=]+)=(.*)\s*$') {
            $envMap[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }

    return $envMap
}

function Require-ConfigValue {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $value = $Config[$Name]
    if (-not $value) {
        throw "Missing required config value: $Name"
    }

    return $value
}

if (-not $ConfigPath) {
    $ConfigPath = Join-Path (Get-SkillRoot) "config.env"
}

if (-not $Quiet) {
    Write-Host "COMSOL Environment Check"
    Write-Host "------------------------"
}

$config = Read-BatEnv -Path $ConfigPath
Write-Check -Status "OK" -Message "Config file: $ConfigPath"

$serverExe = Require-ConfigValue -Config $config -Name "SERVER_BAT"
$guiExe = Require-ConfigValue -Config $config -Name "COMSOL_GUI_EXE"
$serverPort = Require-ConfigValue -Config $config -Name "SERVER_PORT"
$serverArgs = $config["SERVER_ARGS"]

if (-not (Test-Path -LiteralPath $serverExe)) {
    throw "SERVER_BAT does not exist: $serverExe"
}
Write-Check -Status "OK" -Message "SERVER_BAT: $serverExe"

if (-not (Test-Path -LiteralPath $guiExe)) {
    throw "COMSOL_GUI_EXE does not exist: $guiExe"
}
Write-Check -Status "OK" -Message "COMSOL_GUI_EXE: $guiExe"

if ($serverArgs -and $serverArgs -notmatch "(^|\s)-port\s+$serverPort(\s|$)") {
    throw "SERVER_ARGS must use the same port as SERVER_PORT. SERVER_PORT=$serverPort SERVER_ARGS=$serverArgs"
}
Write-Check -Status "OK" -Message "SERVER_ARGS matches SERVER_PORT: $serverArgs"

$portOwner = Get-NetTCPConnection -LocalPort ([int]$serverPort) -ErrorAction SilentlyContinue |
    Where-Object { $_.State -eq "Listen" } |
    Select-Object -First 1
if ($portOwner) {
    $process = Get-Process -Id $portOwner.OwningProcess -ErrorAction SilentlyContinue
    Write-Check -Status "INFO" -Message "Port $serverPort is already listening by PID $($portOwner.OwningProcess) $($process.ProcessName)"
}
else {
    Write-Check -Status "OK" -Message "Port $serverPort is currently free"
}

if ($CheckPython) {
    try {
        $output = & $PythonExe -c "import mph, sys; print(sys.executable); print(getattr(mph, '__version__', 'unknown'))" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw ($output -join "`n")
        }
        Write-Check -Status "OK" -Message "Python mph import works: $($output -join ' | ')"
    }
    catch {
        throw "Python mph check failed. Use -PythonExe to select another Python or install mph. Details: $_"
    }
}
else {
    Write-Check -Status "SKIP" -Message "Python mph check skipped. Use -CheckPython to enable it."
}

Write-Check -Status "OK" -Message "Environment check completed"
