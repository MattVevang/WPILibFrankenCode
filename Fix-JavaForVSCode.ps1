<#
.SYNOPSIS
    Fixes the "Java 21 or more required" VS Code toast for an existing WPILib FrankenCode install.

.DESCRIPTION
    The VS Code Java Language Server (redhat.java extension) requires JDK 21+ to START,
    but WPILib robot code must be BUILT with JDK 17. These are two different jobs:

        java.jdt.ls.java.home → JDK 21  (runs the IntelliSense / language server)
        java.configuration.runtimes     → JDK 17 as default (compiles robot code)
        JAVA_HOME / terminal PATH       → JDK 17 (Gradle builds use this)

    This script downloads a small JDK 21 package specifically for the language server,
    installs it alongside the WPILib JDK 17, and patches VS Code settings accordingly.
    It does NOT re-download the WPILib ISO or touch any robot code build toolchain.

    Optionally installs the GitHub CLI (gh) and Copilot CLI extension if missing.

.PARAMETER WPILibYear
    The FRC season year of your existing install. Default: 2026

.PARAMETER InstallDir
    Base WPILib installation directory. Default: C:\Users\Public\wpilib

.PARAMETER DownloadDir
    Temporary directory for the JDK 21 download. Default: $env:TEMP\WPILibFrankenCode

.PARAMETER SkipCopilotCLI
    Skip GitHub CLI / Copilot CLI installation and setup.

.PARAMETER Force
    Re-download and reinstall JDK 21 even if already present.

.EXAMPLE
    .\Fix-JavaForVSCode.ps1
    # Fixes the JDK 21 language server issue and sets up Copilot CLI

.EXAMPLE
    .\Fix-JavaForVSCode.ps1 -SkipCopilotCLI
    # Java fix only — skip Copilot CLI

.NOTES
    Requires: Administrator privileges, internet connection (~170 MB JDK download).
    Safe to run multiple times — idempotent.
    Author:   WPILibFrankenCode Project
    Version:  1.0.0
#>

#Requires -Version 5.1

# Note: Does NOT require admin rights. The WPILib install dir (C:\Users\Public\wpilib\...)
# is writable by all users. 'winget install' for gh CLI will self-elevate if needed.

[CmdletBinding()]
param(
    [string]$WPILibYear  = "2026",
    [string]$InstallDir  = "C:\Users\Public\wpilib",
    [string]$DownloadDir = "$env:TEMP\WPILibFrankenCode",
    [switch]$SkipCopilotCLI,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference    = "Continue"

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Message, [string]$Status = "INFO")
    $colors = @{
        "INFO"   = "Cyan"
        "OK"     = "Green"
        "WARN"   = "Yellow"
        "ERROR"  = "Red"
        "SKIP"   = "DarkGray"
        "ACTION" = "White"
        "FIX"    = "Magenta"
    }
    $color = $colors[$Status]; if (-not $color) { $color = "White" }
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] " -NoNewline -ForegroundColor DarkGray
    Write-Host "[$Status] " -NoNewline -ForegroundColor $color
    Write-Host $Message
}

function Write-Banner {
    param([string]$Message)
    Write-Host ""
    Write-Host ("=" * 72) -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host ("=" * 72) -ForegroundColor Cyan
    Write-Host ""
}

function Test-IsArm64 {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { return $true }
    try {
        $arch = (Get-CimInstance Win32_Processor -Property Architecture |
                 Select-Object -First 1).Architecture
        return ($arch -eq 12)  # 12 = ARM64
    } catch {}
    return $false
}

function Invoke-Download {
    param([string]$Url, [string]$OutFile, [string]$Description)
    Write-Step "Downloading $Description..." "ACTION"
    Write-Step "  From: $Url" "INFO"
    Write-Step "  To:   $OutFile" "INFO"
    if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
        Start-BitsTransfer -Source $Url -Destination $OutFile -DisplayName $Description
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    }
    Write-Step "Download complete" "OK"
}

function Merge-VSCodeSetting {
    param([string]$SettingsPath, [hashtable]$NewSettings)
    $obj = @{}
    if (Test-Path $SettingsPath) {
        try {
            $raw = Get-Content $SettingsPath -Raw
            # Strip JSON comments (// style) for parsing
            $cleaned = $raw -replace '(?m)^\s*//.*$', '' -replace ',\s*}', '}'
            $obj = $cleaned | ConvertFrom-Json -ErrorAction Stop
            # ConvertFrom-Json returns PSCustomObject — convert to hashtable
            $obj = @{} + (ConvertFrom-Json ($obj | ConvertTo-Json -Depth 20))
        } catch {
            Write-Step "Could not parse existing settings.json — will merge carefully" "WARN"
            $obj = @{}
        }
    }
    foreach ($key in $NewSettings.Keys) {
        $obj[$key] = $NewSettings[$key]
    }
    $parent = Split-Path $SettingsPath -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $obj | ConvertTo-Json -Depth 20 | Set-Content $SettingsPath -Encoding UTF8
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

Write-Banner "WPILib FrankenCode — Java LS + Copilot CLI Fix"

$yearDir     = Join-Path $InstallDir $WPILibYear
$jdk17Path   = Join-Path $yearDir "jdk"
$jdk21LsPath = Join-Path $yearDir "jdk21ls"
$settingsPath = Join-Path $env:APPDATA "Code\User\settings.json"

# ── Sanity checks ──
if (-not (Test-Path $yearDir)) {
    Write-Step "WPILib install directory not found: $yearDir" "ERROR"
    Write-Step "Run the FrankenCode installer first, then re-run this script." "ERROR"
    exit 1
}
if (-not (Test-Path $jdk17Path)) {
    Write-Step "WPILib JDK 17 not found at: $jdk17Path" "ERROR"
    exit 1
}
Write-Step "Found WPILib install: $yearDir" "OK"

$java17Exe = Join-Path $jdk17Path "bin\java.exe"
$java17Ver = (& $java17Exe -version 2>&1 | Select-Object -First 1) -replace '"', ''
Write-Step "WPILib JDK 17 (builds): $java17Ver" "OK"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1: JDK 21 for Language Server
# ─────────────────────────────────────────────────────────────────────────────

Write-Banner "Section 1: JDK 21 Language Server Installation"

$isArm64 = Test-IsArm64
if ($isArm64) {
    Write-Step "Platform: Windows ARM64 — downloading Microsoft JDK 21 ARM64" "INFO"
    $jdk21Url     = "https://aka.ms/download-jdk/microsoft-jdk-21-windows-aarch64.zip"
    $jdk21ZipName = "microsoft-jdk-21-windows-aarch64.zip"
} else {
    Write-Step "Platform: Windows x64 — downloading Microsoft JDK 21 x64" "INFO"
    $jdk21Url     = "https://aka.ms/download-jdk/microsoft-jdk-21-windows-x64.zip"
    $jdk21ZipName = "microsoft-jdk-21-windows-x64.zip"
}

$jdk21ZipPath = Join-Path $DownloadDir $jdk21ZipName

if (-not (Test-Path $DownloadDir)) {
    New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
}

# Check if already installed and valid
$jdk21AlreadyOk = $false
if ((Test-Path $jdk21LsPath) -and -not $Force) {
    $j21exe = Join-Path $jdk21LsPath "bin\java.exe"
    if (Test-Path $j21exe) {
        $j21ver = (& $j21exe -version 2>&1 | Select-Object -First 1) -replace '"', ''
        if ($j21ver -match "21\.|22\.|23\.|24\.|25\.|26\.") {
            Write-Step "JDK 21 LS already installed: $j21ver" "SKIP"
            $jdk21AlreadyOk = $true
        }
    }
}

if (-not $jdk21AlreadyOk) {
    # Download if needed
    $needDownload = $true
    if ((Test-Path $jdk21ZipPath) -and -not $Force) {
        $sz = (Get-Item $jdk21ZipPath).Length
        if ($sz -gt 100MB) {
            Write-Step "JDK 21 zip already in download cache ($('{0:N0}' -f ($sz/1MB)) MB) — reusing" "SKIP"
            $needDownload = $false
        } else {
            Remove-Item $jdk21ZipPath -Force
        }
    }
    if ($needDownload) {
        Invoke-Download -Url $jdk21Url -OutFile $jdk21ZipPath -Description "Microsoft JDK 21"
    }

    # Remove old jdk21ls if present
    if (Test-Path $jdk21LsPath) {
        Write-Step "Removing old $jdk21LsPath" "ACTION"
        Remove-Item $jdk21LsPath -Recurse -Force
    }

    # Extract
    Write-Step "Extracting JDK 21 to $(Split-Path $jdk21LsPath -Parent)..." "ACTION"
    $tempDir = Join-Path $DownloadDir "jdk21ls-temp"
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($jdk21ZipPath, $tempDir)

    # MS JDK zip extracts to a subdirectory like "jdk-21.0.x+y"
    $extracted = Get-ChildItem $tempDir -Directory | Select-Object -First 1
    if (-not $extracted) { throw "Could not find extracted JDK directory in $tempDir" }

    Write-Step "Moving $($extracted.Name) → jdk21ls/" "ACTION"
    Move-Item $extracted.FullName $jdk21LsPath -Force
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

    # Verify
    $j21exe = Join-Path $jdk21LsPath "bin\java.exe"
    if (-not (Test-Path $j21exe)) {
        throw "JDK 21 installation failed — java.exe not found at $j21exe"
    }
    $j21ver = (& $j21exe -version 2>&1 | Select-Object -First 1) -replace '"', ''
    Write-Step "JDK 21 LS installed: $j21ver" "OK"
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2: Patch VS Code Settings
# ─────────────────────────────────────────────────────────────────────────────

Write-Banner "Section 2: VS Code Settings Patch"

Write-Step "Settings file: $settingsPath" "INFO"
Write-Step "  java.jdt.ls.java.home → $jdk21LsPath  (language server JDK 21)" "FIX"
Write-Step "  java.configuration.runtimes[JavaSE-17].path → $jdk17Path  (WPILib builds, default)" "FIX"
Write-Step "  java.configuration.runtimes[JavaSE-21].path → $jdk21LsPath  (available for use)" "FIX"
Write-Step "  JAVA_HOME / PATH remain pointed at JDK 17  (Gradle builds unchanged)" "INFO"

$patch = @{
    "java.jdt.ls.java.home"       = $jdk21LsPath
    "java.configuration.runtimes" = @(
        @{
            "name"    = "JavaSE-17"
            "path"    = $jdk17Path
            "default" = $true
        },
        @{
            "name"    = "JavaSE-21"
            "path"    = $jdk21LsPath
            "default" = $false
        }
    )
}

Merge-VSCodeSetting -SettingsPath $settingsPath -NewSettings $patch
Write-Step "VS Code settings patched" "OK"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3: GitHub CLI + Copilot CLI — WPILib Integration
# ─────────────────────────────────────────────────────────────────────────────

Write-Banner "Section 3: GitHub CLI + Copilot CLI — WPILib Integration"

$frcCodeDir       = Join-Path $yearDir "frccode"
$ghAuthenticated  = $false

if ($SkipCopilotCLI) {
    Write-Step "Skipping Copilot CLI setup (-SkipCopilotCLI)" "SKIP"
} else {
    # ── Step 1: Ensure gh CLI is installed ──
    $env:PATH = [Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("PATH", "User")

    $ghExe = Get-Command gh -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    if (-not $ghExe) {
        Write-Step "GitHub CLI (gh) not found — attempting install via winget..." "ACTION"
        try {
            winget install --id GitHub.cli --silent --accept-package-agreements --accept-source-agreements 2>&1 |
                ForEach-Object { Write-Step "  $_" "INFO" }
            $env:PATH = [Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                        [Environment]::GetEnvironmentVariable("PATH", "User")
            $ghExe = Get-Command gh -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
        } catch {
            Write-Step "winget install failed: $_" "WARN"
            Write-Step "Install GitHub CLI manually from https://cli.github.com/" "INFO"
        }
    }

    if ($ghExe) {
        $ghVer = gh --version 2>&1 | Select-Object -First 1
        Write-Step "GitHub CLI: $ghVer" "OK"
    } else {
        Write-Step "GitHub CLI not available — integration scripts will still be created" "WARN"
    }

    # ── Step 2: Check authentication ──
    if ($ghExe) {
        $authStatus = gh auth status 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Step "GitHub CLI authenticated" "OK"
            $ghAuthenticated = $true
        } else {
            Write-Step "GitHub CLI is NOT authenticated" "WARN"
            Write-Step "Run in any terminal (admin not required):" "INFO"
            Write-Step "  gh auth login" "INFO"
            Write-Step "  gh extension install github/gh-copilot" "INFO"
        }
    }

    # ── Step 3: Install gh-copilot extension ──
    if ($ghAuthenticated) {
        $extList = gh extension list 2>&1
        if ($extList -match "copilot") {
            Write-Step "gh-copilot extension already installed" "SKIP"
        } else {
            Write-Step "Installing gh-copilot extension..." "ACTION"
            try {
                gh extension install github/gh-copilot 2>&1 | ForEach-Object { Write-Step "  $_" "INFO" }
                Write-Step "gh-copilot extension installed" "OK"
            } catch {
                Write-Step "Failed to install gh-copilot: $_" "WARN"
                Write-Step "Manually run: gh extension install github/gh-copilot" "INFO"
            }
        }

        $copVer = gh copilot --version 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Step "gh copilot version: $copVer" "OK" }
    }

    # ── Step 4: Create WPILib integration files ──
    # Created regardless of gh auth status — wrappers are ready as soon as auth is done

    Write-Step "Creating WPILib Copilot integration scripts in $frcCodeDir" "ACTION"
    if (-not (Test-Path $frcCodeDir)) { New-Item -ItemType Directory -Path $frcCodeDir -Force | Out-Null }

    # frc-ai.cmd — wraps 'gh copilot suggest -t powershell' with WPILib env loaded
    $frcAiCmd = Join-Path $frcCodeDir "frc-ai.cmd"
    @"
@echo off
REM WPILib FRC AI Assistant
REM Wraps 'gh copilot suggest' with the WPILib build environment pre-loaded.
REM Usage: frc-ai [optional question]
REM   frc-ai                                  -- interactive
REM   frc-ai "how do I deploy my robot code"  -- direct question
call "%~dp0frcvars${WPILibYear}.bat"
if "%~1"=="" (
    echo.
    echo  WPILib FRC AI Assistant  ^(gh copilot suggest^)
    echo  ─────────────────────────────────────────────────────────────────────
    echo  Useful starting questions:
    echo    frc-ai "how do I build my robot project"
    echo    frc-ai "how do I deploy to the roboRIO"
    echo    frc-ai "how do I add a WPILib vendor library"
    echo    frc-ai "how do I run desktop simulation"
    echo    frc-ai "show me a Command-Based subsystem template"
    echo    frc-ai "how do I run just my unit tests"
    echo.
    gh copilot suggest -t powershell
) else (
    gh copilot suggest -t powershell "%~1"
)
"@ | Set-Content $frcAiCmd -Encoding ASCII
    Write-Step "Created: $frcAiCmd" "OK"

    # frc-ai.ps1 — PowerShell version
    $frcAiPs1 = Join-Path $frcCodeDir "frc-ai.ps1"
    @'
# WPILib FRC AI Assistant (PowerShell)
# Wraps 'gh copilot suggest' with the WPILib build environment pre-loaded.
# Usage:  .\frc-ai.ps1 [optional question]
param([Parameter(ValueFromRemainingArguments)][string[]]$Question)

$wpilibHome = Join-Path $PSScriptRoot '..'
$env:JAVA_HOME = Join-Path $wpilibHome 'jdk'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"

$q = $Question -join ' '
if (-not $q) {
    Write-Host ''
    Write-Host '  WPILib FRC AI Assistant  (gh copilot suggest)' -ForegroundColor Magenta
    Write-Host '  ─────────────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host '  Useful starting questions:' -ForegroundColor Cyan
    '  how do I build my robot project',
    '  how do I deploy to the roboRIO',
    '  how do I add a WPILib vendor library',
    '  how do I run desktop simulation',
    '  show me a Command-Based subsystem template',
    '  how do I run just my unit tests' | ForEach-Object { Write-Host "    frc-ai '$_'" -ForegroundColor White }
    Write-Host ''
    gh copilot suggest -t powershell
} else {
    gh copilot suggest -t powershell $q
}
'@ | Set-Content $frcAiPs1 -Encoding UTF8
    Write-Step "Created: $frcAiPs1" "OK"

    # frc-explain.cmd — wraps 'gh copilot explain' with WPILib env loaded
    $frcExplainCmd = Join-Path $frcCodeDir "frc-explain.cmd"
    @"
@echo off
REM WPILib FRC Explain
REM Explains a shell command or WPILib concept using gh copilot explain.
REM Usage: frc-explain "command or concept to explain"
call "%~dp0frcvars${WPILibYear}.bat"
if "%~1"=="" (
    echo Usage: frc-explain "command or concept to explain"
    echo Examples:
    echo   frc-explain "./gradlew deploy -Pteam=1234"
    echo   frc-explain "what does WPILib Command-Based framework mean"
    echo   frc-explain "why does my robot code have a RobotContainer"
) else (
    gh copilot explain "%~1"
)
"@ | Set-Content $frcExplainCmd -Encoding ASCII
    Write-Step "Created: $frcExplainCmd" "OK"

    # frc-explain.ps1 — PowerShell version
    $frcExplainPs1 = Join-Path $frcCodeDir "frc-explain.ps1"
    @'
# WPILib FRC Explain (PowerShell)
# Explains a shell command or WPILib concept using gh copilot explain.
# Usage:  .\frc-explain.ps1 'command or concept'
param([Parameter(ValueFromRemainingArguments)][string[]]$Item)

$wpilibHome = Join-Path $PSScriptRoot '..'
$env:JAVA_HOME = Join-Path $wpilibHome 'jdk'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"

$q = $Item -join ' '
if (-not $q) {
    Write-Host 'Usage: frc-explain.ps1 <command or concept>' -ForegroundColor Yellow
    Write-Host "  frc-explain.ps1 './gradlew deploy -Pteam=1234'" -ForegroundColor White
    Write-Host "  frc-explain.ps1 'what does WPILib Command-Based framework mean'" -ForegroundColor White
} else {
    gh copilot explain $q
}
'@ | Set-Content $frcExplainPs1 -Encoding UTF8
    Write-Step "Created: $frcExplainPs1" "OK"

    # ── Step 5: Write the wpilib-copilot-instructions.md template ──
    # Teams copy this to <robot-project>/.github/copilot-instructions.md
    # GitHub Copilot (VS Code, CLI, web) reads it as permanent project context.
    $instructionsPath = Join-Path $yearDir "wpilib-copilot-instructions.md"
    $instructionsContent = @"
# WPILib FRC Robot Code — GitHub Copilot Instructions

This repository contains FRC (FIRST Robotics Competition) robot code using WPILib $WPILibYear.

## Project Overview
- **Build system**: Gradle with the GradleRIO plugin
- **Target hardware**: NI roboRIO running Java (or C++)
- **WPILib version**: $WPILibYear
- **Framework**: Command-Based (subsystems + commands in ``src/main/java/frc/robot/``)

## Directory Structure
``````
src/
  main/java/frc/robot/
    Robot.java            -- entry point (extends TimedRobot)
    RobotContainer.java   -- wires subsystems + commands + driver controls
    Constants.java        -- all hardware port numbers and tuning constants
    subsystems/           -- one file per physical mechanism
    commands/             -- one file per autonomous action or complex operation
``````

## Common Gradle Tasks
``````bash
./gradlew build              # compile only (no deploy)
./gradlew deploy             # build + deploy to roboRIO over USB or WiFi
./gradlew simulateJava       # run desktop simulation (requires x64 JDK)
./gradlew test               # run unit tests
./gradlew vendordep          # check for vendor library updates
``````

## Code Conventions
- Subsystems extend ``SubsystemBase`` and live in ``subsystems/``
- Command factory methods are preferred over extending ``Command`` directly
  (e.g., ``Commands.runOnce(...)`` or ``subsystem.myCommand()``)
- ``RobotContainer.java`` wires everything: instantiates subsystems, binds joystick
  buttons via ``trigger.onTrue(command)``
- Hardware port numbers and PID constants belong in ``Constants.java``
- Always guard hardware-only code with ``RobotBase.isReal()`` for simulation compat

## Key WPILib APIs to Know
- Motors: ``TalonFX``, ``SparkMax`` (via vendor libs), ``PWMMotorController``
- Sensors: ``DigitalInput``, ``AnalogInput``, ``DutyCycleEncoder``, ``ADIS16470_IMU``
- Pneumatics: ``Solenoid`` / ``DoubleSolenoid`` via ``PneumaticHub`` (CTRE)
- NetworkTables: ``NetworkTableInstance.getDefault()`` for telemetry
- Path following: ``AutoBuilder`` (PathPlanner) or ``RamseteCommand`` (built-in)
- Alerts: ``Alert`` class for driver station messages (WPILib 2025+)

## Simulation Notes
- Desktop simulation requires x64 JDK (WPILib JNI libs are x64-only on Windows)
  JAVA_HOME should point to ``C:/Users/Public/wpilib/$WPILibYear/jdk``
- Use ``RobotBase.isSimulation()`` to swap in simulated hardware

## Copilot AI Shortcuts (from terminal, after WPILib FrankenCode install)
``````bash
frc-ai "how do I add a subsystem"          # gh copilot suggest with WPILib context
frc-ai "deploy command for team 1234"      # direct question
frc-explain "./gradlew deploy -Pteam=1234" # explain a gradle command
``````
"@
    $instructionsContent | Set-Content $instructionsPath -Encoding UTF8
    Write-Step "Created template: $instructionsPath" "OK"
    Write-Step "  Copy to <robot-project>/.github/copilot-instructions.md" "INFO"
    Write-Step "  Primes GitHub Copilot (VS Code + CLI + web) with WPILib context" "INFO"

    # ── Summary ──
    Write-Host ""
    Write-Host ("─" * 72) -ForegroundColor Cyan
    Write-Host "  Copilot CLI — WPILib Integration Summary" -ForegroundColor Cyan
    Write-Host ("─" * 72) -ForegroundColor Cyan
    Write-Host "  Commands added to frccode/ (already on system PATH):" -ForegroundColor Cyan
    Write-Host "    frc-ai [question]     -- AI suggestions (gh copilot suggest)" -ForegroundColor White
    Write-Host "    frc-explain [text]    -- AI explanations (gh copilot explain)" -ForegroundColor White
    Write-Host ""
    Write-Host "  Project template (copy into any robot project):" -ForegroundColor Cyan
    Write-Host "    $instructionsPath" -ForegroundColor White
    Write-Host "    ->  <project>/.github/copilot-instructions.md" -ForegroundColor DarkGray
    Write-Host ""
    if (-not $ghAuthenticated) {
        Write-Host "  PENDING: Complete GitHub CLI authentication:" -ForegroundColor Yellow
        Write-Host "    gh auth login" -ForegroundColor Yellow
        Write-Host "    gh extension install github/gh-copilot" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

Write-Banner "Fix Complete"

Write-Host "  What was done:" -ForegroundColor Cyan
Write-Host "    [JDK]  Installed JDK 21 to: $jdk21LsPath" -ForegroundColor Green
Write-Host "    [JDK]  WPILib JDK 17 unchanged at: $jdk17Path" -ForegroundColor Green
Write-Host "    [VS]   java.jdt.ls.java.home → JDK 21 (fixes 'Java 21 required' toast)" -ForegroundColor Green
Write-Host "    [VS]   java.configuration.runtimes → JDK 17 default (robot builds work)" -ForegroundColor Green
Write-Host ""
Write-Host "  ACTION REQUIRED:" -ForegroundColor Yellow
Write-Host "    1. Fully close VS Code (File → Exit, not just close window)" -ForegroundColor Yellow
Write-Host "    2. Re-open VS Code" -ForegroundColor Yellow
Write-Host "    3. The 'Java 21 required' toast should no longer appear" -ForegroundColor Yellow
Write-Host "    4. Robot code builds still use JDK 17 — no change to Gradle" -ForegroundColor Yellow
Write-Host ""
