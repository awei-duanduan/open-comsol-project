# Open COMSOL Project / 打开 COMSOL 项目

English | [中文](#中文)

## English

`open-comsol-project` is a Codex skill for Windows COMSOL workflows. It starts `comsolmphserver.exe`, waits for the configured server port, opens COMSOL Multiphysics, and optionally auto-opens a user-provided `.mph` model.

### What It Does

- Starts COMSOL Server / `mphserver`.
- Opens COMSOL GUI directly through `comsol.exe`.
- Auto-opens a `.mph` file when a model path is provided.
- Opens COMSOL GUI without a model when no path is provided.
- Optionally verifies a loaded model through Python `mph`.
- Provides quick TCP checks for `localhost:2038`.

### Requirements

- Windows.
- COMSOL Multiphysics installed.
- A COMSOL license that allows `comsolmphserver.exe`.
- PowerShell.
- Optional for Python probing: Python with the `mph` package installed.

### Installation

Copy or clone this skill folder into your Codex skills directory.

Example:

```powershell
git clone https://github.com/awei-duanduan/open-comsol-project.git
```

### First-Time Setup

Run the initializer once on each new machine:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Initialize-ComsolSkill.ps1"
```

The initializer will:

- Search common COMSOL installation paths.
- Show detected `comsolmphserver.exe` and `comsol.exe`.
- Let you press Enter to accept detected paths.
- Prompt you to type paths manually if detection fails.
- Create a local `config.env`.

Do not commit `config.env`. It is machine-specific and is ignored by `.gitignore`.

### Configuration

The generated `config.env` follows this shape:

```bat
set "SERVER_HOST=localhost"
set "SERVER_PORT=2038"
set "SERVER_ARGS=-port 2038"
set "STARTUP_TIMEOUT_SECONDS=120"
set "PROBE_TIMEOUT_SECONDS=45"
set "SERVER_BAT=C:\Path\To\COMSOL\Multiphysics\bin\win64\comsolmphserver.exe"
set "COMSOL_GUI_EXE=C:\Path\To\COMSOL\Multiphysics\bin\win64\comsol.exe"
set "COMSOL_GUI_LNK="
```

You can also inspect `config.example.env`.

### Usage

Start COMSOL Server and open COMSOL GUI:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Start-ComsolWorkflow.ps1"
```

Start COMSOL Server and auto-open a model:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Start-ComsolWorkflow.ps1" "C:\path\to\model.mph"
```

Run the optional Python probe after opening a model:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Start-ComsolWorkflow.ps1" "C:\path\to\model.mph" -Probe
```

Start only COMSOL Server:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Start-ComsolServer.ps1"
```

### Check Connection Status

Check whether COMSOL Server is listening:

```powershell
Get-NetTCPConnection -LocalPort 2038 -ErrorAction SilentlyContinue
```

Check whether COMSOL GUI is connected to the server:

```powershell
Get-NetTCPConnection -RemotePort 2038 -ErrorAction SilentlyContinue
```

A successful connection usually shows:

- `comsolmphserver.exe` listening on local port `2038`.
- `comsol.exe` with an `Established` connection to remote port `2038`.

### Disconnect COMSOL Server

Stop the `comsolmphserver.exe` process that owns local port `2038`:

```powershell
$serverPids = Get-NetTCPConnection -LocalPort 2038 -ErrorAction SilentlyContinue |
    Where-Object { $_.State -eq 'Listen' } |
    Select-Object -ExpandProperty OwningProcess -Unique

foreach ($serverPid in $serverPids) {
    $proc = Get-Process -Id $serverPid -ErrorAction SilentlyContinue
    if ($proc -and $proc.ProcessName -eq 'comsolmphserver') {
        Stop-Process -Id $serverPid -Force
    }
}
```

This disconnects the server session without intentionally closing COMSOL GUI.

### Troubleshooting

- If startup fails, rerun `Initialize-ComsolSkill.ps1 -Force`.
- If the configured port is busy, change both `SERVER_PORT` and `SERVER_ARGS`.
- If Python probing hangs, first check TCP connections; GUI may still be connected.
- If Python cannot import `mph`, install/configure the Python environment used by COMSOL automation.
- If multiple `comsolmphserver.exe` processes exist, identify the one owning the configured local port.

---

## 中文

`open-comsol-project` 是一个用于 Windows COMSOL 工作流的 Codex skill。它可以启动 `comsolmphserver.exe`，等待指定端口就绪，打开 COMSOL Multiphysics，并在用户提供 `.mph` 路径时自动打开模型。

### 功能

- 启动 COMSOL Server / `mphserver`。
- 通过 `comsol.exe` 直接打开 COMSOL GUI。
- 如果提供 `.mph` 路径，自动打开该模型。
- 如果未提供模型路径，只打开 COMSOL GUI。
- 可选：通过 Python `mph` 对已加载模型做只读探测。
- 提供 `localhost:2038` 的 TCP 连接检查方法。

### 环境要求

- Windows。
- 已安装 COMSOL Multiphysics。
- COMSOL 许可证允许启动 `comsolmphserver.exe`。
- PowerShell。
- 可选 Python 探测：Python 环境已安装 `mph` 包。

### 安装

将本 skill 文件夹复制或克隆到你的 Codex skills 目录。

示例：

```powershell
git clone https://github.com/awei-duanduan/open-comsol-project.git
```

### 首次初始化

每台新机器首次使用前运行一次：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Initialize-ComsolSkill.ps1"
```

初始化脚本会：

- 搜索常见 COMSOL 安装路径。
- 显示检测到的 `comsolmphserver.exe` 和 `comsol.exe`。
- 允许你直接按 Enter 接受检测结果。
- 如果检测失败，会提示你手动输入路径。
- 生成本地 `config.env`。

不要提交 `config.env`。它是本机专属配置，已经被 `.gitignore` 忽略。

### 配置文件

生成的 `config.env` 格式如下：

```bat
set "SERVER_HOST=localhost"
set "SERVER_PORT=2038"
set "SERVER_ARGS=-port 2038"
set "STARTUP_TIMEOUT_SECONDS=120"
set "PROBE_TIMEOUT_SECONDS=45"
set "SERVER_BAT=C:\Path\To\COMSOL\Multiphysics\bin\win64\comsolmphserver.exe"
set "COMSOL_GUI_EXE=C:\Path\To\COMSOL\Multiphysics\bin\win64\comsol.exe"
set "COMSOL_GUI_LNK="
```

也可以参考 `config.example.env`。

### 使用方法

启动 COMSOL Server 并打开 COMSOL GUI：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Start-ComsolWorkflow.ps1"
```

启动 COMSOL Server 并自动打开模型：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Start-ComsolWorkflow.ps1" "C:\path\to\model.mph"
```

打开模型后运行可选 Python 探测：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Start-ComsolWorkflow.ps1" "C:\path\to\model.mph" -Probe
```

只启动 COMSOL Server：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Start-ComsolServer.ps1"
```

### 检查连接状态

检查 COMSOL Server 是否正在监听：

```powershell
Get-NetTCPConnection -LocalPort 2038 -ErrorAction SilentlyContinue
```

检查 COMSOL GUI 是否连接到 server：

```powershell
Get-NetTCPConnection -RemotePort 2038 -ErrorAction SilentlyContinue
```

连接成功时通常会看到：

- `comsolmphserver.exe` 正在监听本地端口 `2038`。
- `comsol.exe` 对远端端口 `2038` 有一个 `Established` 连接。

### 断开 COMSOL Server

停止占用本地端口 `2038` 的 `comsolmphserver.exe` 进程：

```powershell
$serverPids = Get-NetTCPConnection -LocalPort 2038 -ErrorAction SilentlyContinue |
    Where-Object { $_.State -eq 'Listen' } |
    Select-Object -ExpandProperty OwningProcess -Unique

foreach ($serverPid in $serverPids) {
    $proc = Get-Process -Id $serverPid -ErrorAction SilentlyContinue
    if ($proc -and $proc.ProcessName -eq 'comsolmphserver') {
        Stop-Process -Id $serverPid -Force
    }
}
```

这会断开 server 会话，不会主动关闭 COMSOL GUI。

### 常见问题

- 如果启动失败，重新运行 `Initialize-ComsolSkill.ps1 -Force`。
- 如果端口被占用，同时修改 `SERVER_PORT` 和 `SERVER_ARGS`。
- 如果 Python 探测卡住，先检查 TCP 连接；GUI 可能已经连接成功。
- 如果 Python 无法导入 `mph`，请配置用于 COMSOL 自动化的 Python 环境。
- 如果存在多个 `comsolmphserver.exe`，优先识别占用配置端口的那个进程。
