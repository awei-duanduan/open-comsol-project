param(
    [string]$ConfigPath,
    [switch]$NoInitialize
)

$ErrorActionPreference = "Stop"

function Get-SkillRoot {
    return (Split-Path -Parent $PSScriptRoot)
}

if (-not $ConfigPath) {
    $ConfigPath = Join-Path (Get-SkillRoot) "config.env"
}

function Ensure-Config {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -LiteralPath $Path) {
        return
    }

    $initScript = Join-Path $PSScriptRoot "Initialize-ComsolSkill.ps1"
    if ($NoInitialize) {
        throw "Config file not found: $Path. Run first: powershell -NoProfile -ExecutionPolicy Bypass -File `"$initScript`""
    }

    Write-Host "Config file not found: $Path"
    Write-Host "Starting first-use initialization..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File $initScript -ConfigPath $Path
    if ($LASTEXITCODE -ne 0) {
        throw "First-use initialization failed."
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Initialization finished but config file was not created: $Path"
    }
}

Ensure-Config -Path $ConfigPath

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

function Test-TcpPort {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port
    )

    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $task = $client.ConnectAsync($HostName, $Port)
        $connected = $task.Wait(350) -and $client.Connected
        $client.Close()
        return $connected
    }
    catch {
        return $false
    }
}

function Wait-TcpPort {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-TcpPort -HostName $HostName -Port $Port) {
            return $true
        }
        Start-Sleep -Milliseconds 250
    }

    return $false
}

$config = Read-BatEnv -Path $ConfigPath

$serverHost = $config["SERVER_HOST"]
if (-not $serverHost) { $serverHost = "localhost" }

$serverPortText = $config["SERVER_PORT"]
if (-not $serverPortText) { $serverPortText = "2038" }
$serverPort = [int]$serverPortText

$timeoutText = $config["STARTUP_TIMEOUT_SECONDS"]
if (-not $timeoutText) { $timeoutText = "120" }
$timeoutSeconds = [int]$timeoutText

$serverExe = $config["SERVER_BAT"]
$serverArgs = $config["SERVER_ARGS"]
if (-not $serverExe -or -not (Test-Path -LiteralPath $serverExe)) {
    throw "SERVER_BAT is missing or invalid. Check $ConfigPath"
}
if (-not $serverArgs) {
    $serverArgs = "-port $serverPort"
}

if (Test-TcpPort -HostName $serverHost -Port $serverPort) {
    Write-Host "COMSOL Server is already reachable at ${serverHost}:$serverPort."
    exit 0
}

Write-Host "Starting COMSOL Server: $serverExe"
Start-Process -FilePath $serverExe -ArgumentList $serverArgs -WindowStyle Normal

Write-Host "Waiting for COMSOL Server at ${serverHost}:$serverPort ..."
if (-not (Wait-TcpPort -HostName $serverHost -Port $serverPort -TimeoutSeconds $timeoutSeconds)) {
    throw "COMSOL Server did not become reachable within $timeoutSeconds seconds."
}

Write-Host "COMSOL Server is reachable at ${serverHost}:$serverPort."
