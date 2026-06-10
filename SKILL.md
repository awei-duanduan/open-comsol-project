---
name: open-comsol-project
description: Use when the user wants to start COMSOL, use COMSOL Server or mphserver, initialize COMSOL executable paths, auto-open an .mph model, open COMSOL GUI without a model, monitor localhost:2038, or run a Python mph probe.
---

# Open COMSOL Project

Use this skill for a Windows COMSOL Server workflow.

## First Use

Before starting COMSOL on a new machine, initialize local paths:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-root>\scripts\Initialize-ComsolSkill.ps1"
```

The initializer searches common COMSOL install locations. It shows detected `comsolmphserver.exe` and `comsol.exe` paths, lets the user press Enter to accept them, or prompts the user to type paths manually. It writes a local `config.env` next to this `SKILL.md`.

Do not commit `config.env`; commit only `config.example.env`.

## Standard Workflow

When the user does not specify a model path, start `mphserver` and open COMSOL GUI directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-root>\scripts\Start-ComsolWorkflow.ps1"
```

When the user specifies a model path, start `mphserver` and auto-open that `.mph` file in COMSOL GUI:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-root>\scripts\Start-ComsolWorkflow.ps1" "C:\path\to\model.mph"
```

The script starts `comsolmphserver.exe`, waits for the configured TCP port, then opens `comsol.exe`. If a model path was provided, it passes the path directly to `comsol.exe` so the project opens without manual file selection.

The Python probe is optional. Use `-Probe` only when the user asks to read or verify the model through Python:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-root>\scripts\Start-ComsolWorkflow.ps1" "C:\path\to\model.mph" -Probe
```

## Fast Checks

Check whether the server is listening:

```powershell
Get-NetTCPConnection -LocalPort 2038 -ErrorAction SilentlyContinue
```

Check whether GUI is connected to the same server:

```powershell
Get-NetTCPConnection -RemotePort 2038 -ErrorAction SilentlyContinue
```

A successful GUI connection usually shows `comsol.exe` with an `Established` connection to the configured server port, and `comsolmphserver.exe` listening on that local port.

## Python Probe

Use the probe only after COMSOL GUI has opened the model:

```powershell
python "<skill-root>\scripts\comsol_mph_probe.py" --host localhost --port 2038
```

If the probe hangs, do not treat that as proof that the GUI connection failed. First inspect TCP connections and COMSOL process titles. The GUI may be connected even when Python `mph` cannot complete the Java handshake.

## Diagnostics

- Multiple `comsolmphserver.exe` processes can exist; identify the one owning the configured local port.
- If Python probe fails, check `python -c "import mph; print(mph.__version__)"`.
- If GUI opened but Python sees no model, the model may be loaded in a different server session.
- Prefer direct `comsol.exe` launch over Start Menu shortcuts for speed.
- Avoid long blind sleeps; use TCP polling on the configured server port.
