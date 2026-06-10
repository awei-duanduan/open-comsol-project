param(
    [Parameter(Position = 0)]
    [string]$ModelPath,

    [string]$ConfigPath,
    [string]$PythonExe = "python",
    [int]$ProbeTimeoutSeconds = 45,
    [switch]$BlankModel,
    [switch]$Probe,
    [switch]$SkipProbe,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

function Show-Usage {
    Write-Host "Usage:"
    Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File .\Start-ComsolWorkflow.ps1 <model.mph>"
    Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File .\Start-ComsolWorkflow.ps1"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -ModelPath <path>     Auto-open model path in COMSOL GUI after mphserver starts."
    Write-Host "  -BlankModel           Explicitly open COMSOL GUI without a model."
    Write-Host "  -Probe                Run the Python probe after COMSOL GUI opens."
    Write-Host "  -SkipProbe            Compatibility alias: do not run the Python probe."
    Write-Host "  -PythonExe <path>     Python executable that has the 'mph' package installed."
    Write-Host "  -ProbeTimeoutSeconds  Maximum seconds to wait for the Python probe. Default: 45."
    Write-Host "  -ConfigPath <path>    Configuration file with COMSOL paths and server settings."
    Write-Host "  -Help                 Show this help."
    Write-Host ""
    Write-Host "Workflow:"
    Write-Host "  1. Start COMSOL Server / mphserver."
    Write-Host "  2. Wait until the configured TCP port is reachable."
    Write-Host "  3. Auto-open model in COMSOL GUI when ModelPath is provided."
    Write-Host "  4. Open COMSOL GUI without a model when ModelPath is omitted."
    Write-Host "  5. Optional Python probe: connect with mph.Client and print a read-only model summary."
}

function Get-SkillRoot {
    return (Split-Path -Parent $PSScriptRoot)
}

function Resolve-DefaultConfigPath {
    if ($ConfigPath) {
        return $ConfigPath
    }

    return (Join-Path (Get-SkillRoot) "config.env")
}

function Assert-ConfigExists {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        $initScript = Join-Path $PSScriptRoot "Initialize-ComsolSkill.ps1"
        throw "Config file not found: $Path. Run first: powershell -NoProfile -ExecutionPolicy Bypass -File `"$initScript`""
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

function Quote-CommandArgument {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    return '"' + ($Value -replace '"', '\"') + '"'
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

function Start-ProbeWithTimeout {
    param(
        [Parameter(Mandatory = $true)][string]$PythonExe,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    $argumentLine = ($Arguments | ForEach-Object { Quote-CommandArgument $_ }) -join " "

    $process = Start-Process `
        -FilePath $PythonExe `
        -ArgumentList $argumentLine `
        -NoNewWindow `
        -PassThru `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $stdout = Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
        if ($stdout) { Write-Host $stdout.TrimEnd() }
        if ($stderr) { Write-Error $stderr.TrimEnd() }
        Remove-Item -LiteralPath $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue
        throw "Python probe timed out after $TimeoutSeconds seconds."
    }

    $stdout = Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue
    $stderr = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
    if ($stdout) { Write-Host $stdout.TrimEnd() }
    if ($stderr) { Write-Error $stderr.TrimEnd() }
    Remove-Item -LiteralPath $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue

    return $process.ExitCode
}

function Start-ComsolGui {
    param(
        [Parameter(Mandatory = $true)][string]$GuiExe,
        [string]$ModelPath,
        [string]$GuiShortcut
    )

    try {
        if ($ModelPath) {
            Write-Host "Launching COMSOL GUI from executable and auto-opening model."
            Start-Process -FilePath $GuiExe -ArgumentList @($ModelPath)
        }
        else {
            Write-Host "Launching COMSOL GUI from executable."
            Start-Process -FilePath $GuiExe
        }
    }
    catch {
        if ($GuiShortcut -and (Test-Path -LiteralPath $GuiShortcut)) {
            Write-Host "Executable launch failed; launching COMSOL GUI from Start Menu shortcut."
            Start-Process -FilePath "explorer.exe" -ArgumentList @($GuiShortcut)
        }
        else {
            throw
        }
    }
}

$ConfigPath = Resolve-DefaultConfigPath

if ($Help) {
    Show-Usage
    exit 0
}

if ($BlankModel -or -not $ModelPath) {
    $resolvedModel = $null
}
else {
    $resolvedModel = (Resolve-Path -LiteralPath $ModelPath).Path
}

Assert-ConfigExists -Path $ConfigPath
$config = Read-BatEnv -Path $ConfigPath

$serverHost = $config["SERVER_HOST"]
if (-not $serverHost) { $serverHost = "localhost" }

$serverPortText = $config["SERVER_PORT"]
if (-not $serverPortText) { $serverPortText = "2038" }
$serverPort = [int]$serverPortText

$timeoutText = $config["STARTUP_TIMEOUT_SECONDS"]
if (-not $timeoutText) { $timeoutText = "90" }
$timeoutSeconds = [int]$timeoutText
$probeTimeoutText = $config["PROBE_TIMEOUT_SECONDS"]
if ($probeTimeoutText -and -not $PSBoundParameters.ContainsKey("ProbeTimeoutSeconds")) {
    $ProbeTimeoutSeconds = [int]$probeTimeoutText
}
$serverBat = $config["SERVER_BAT"]
$serverArgs = $config["SERVER_ARGS"]
$guiExe = $config["COMSOL_GUI_EXE"]
$guiLnk = $config["COMSOL_GUI_LNK"]

if (-not $serverBat -or -not (Test-Path -LiteralPath $serverBat)) {
    throw "SERVER_BAT is missing or invalid. Check $ConfigPath"
}

if (-not $guiExe -or -not (Test-Path -LiteralPath $guiExe)) {
    throw "COMSOL_GUI_EXE is missing or invalid. Check $ConfigPath"
}

if (-not $serverArgs) {
    $serverArgs = "-port $serverPort"
}

Write-Host "COMSOL Server / GUI / Python probe workflow"
Write-Host "------------------------------------------"
if ($BlankModel) {
    Write-Host "Model: blank model workflow"
}
else {
    Write-Host "Model: $resolvedModel"
}
Write-Host "Server: ${serverHost}:$serverPort"
Write-Host "Server executable: $serverBat"
Write-Host "Server arguments: $serverArgs"
Write-Host "GUI executable: $guiExe"
Write-Host "Python probe timeout: $ProbeTimeoutSeconds seconds"
Write-Host ""

if (Test-TcpPort -HostName $serverHost -Port $serverPort) {
    Write-Host "COMSOL Server is already reachable."
}
else {
    Write-Host "Starting COMSOL Server..."
    Start-Process -FilePath $serverBat -ArgumentList $serverArgs -WindowStyle Normal
}

Write-Host "Waiting for COMSOL Server at ${serverHost}:$serverPort ..."
if (-not (Wait-TcpPort -HostName $serverHost -Port $serverPort -TimeoutSeconds $timeoutSeconds)) {
    throw "COMSOL Server did not become reachable within $timeoutSeconds seconds. Check that SERVER_ARGS uses the same port as SERVER_PORT in $ConfigPath."
}

Write-Host "COMSOL Server is reachable at ${serverHost}:$serverPort."

Start-ComsolGui -GuiExe $guiExe -ModelPath $resolvedModel -GuiShortcut $guiLnk

Write-Host ""
if ($resolvedModel) {
    Write-Host "Auto-open model:"
    Write-Host "  $resolvedModel"
}
else {
    Write-Host "Opened COMSOL GUI without a model path."
}
Write-Host "Server remains available at ${serverHost}:$serverPort."
Write-Host ""

if ($SkipProbe -or -not $Probe) {
    Write-Host "Skipping Python/mph probe."
    exit 0
}

if ($BlankModel) {
    Read-Host "After the GUI visibly shows the new blank model, press Enter to run the Python probe"
}
else {
    Read-Host "After the GUI visibly shows the target model, press Enter to run the Python probe"
}

$probeScript = Join-Path $PSScriptRoot "comsol_mph_probe.py"
if (-not (Test-Path -LiteralPath $probeScript)) {
    throw "Probe script not found: $probeScript"
}

$probeArgs = @($probeScript, "--host", $serverHost, "--port", [string]$serverPort)
if (-not $BlankModel) {
    $probeArgs += @("--model", $resolvedModel)
}

$probeExitCode = Start-ProbeWithTimeout -PythonExe $PythonExe -Arguments $probeArgs -TimeoutSeconds $ProbeTimeoutSeconds
if ($probeExitCode -ne 0) {
    throw "Python probe failed with exit code $probeExitCode. Confirm Python can import 'mph' and that the GUI model is loaded in ${serverHost}:$serverPort."
}

Write-Host ""
if ($BlankModel) {
    Write-Host "COMSOL blank model is visible and the mph probe completed."
}
else {
    Write-Host "COMSOL project is visibly opened and the mph probe completed."
}
