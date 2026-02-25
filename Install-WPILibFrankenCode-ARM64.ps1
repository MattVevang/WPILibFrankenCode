<#
.SYNOPSIS
    WPILib FrankenCode Installer (ARM64) — Installs WPILib 2026 on Windows ARM64.

.DESCRIPTION
    Variant of the FrankenCode installer adapted for Windows 11 ARM64 (Snapdragon X,
    Surface Pro, etc.). Downloads the official WPILib 2026.2.1 x64 ISO and extracts
    all development artifacts, with ARM64-specific adaptations:

    ● JDK 17 — Uses the x64 Temurin JDK from the ISO under Prism emulation by default.
      This ensures full compatibility with simulation and unit tests (see KNOWN
      LIMITATIONS below). Use -UseArm64Jdk to opt in to a native ARM64 JDK instead.
    ● JDK 21 (Language Server) — Downloads Microsoft JDK 21 ARM64 and installs it to
      jdk21ls/. Used ONLY to start the VS Code Java Language Server (redhat.java
      extension requires JDK 21+ since v1.30). Robot code compilation still targets
      JDK 17. The LS is pure Java and never touches WPILib JNI, so ARM64-native is safe.
    ● VS Code Extensions — Installs cpptools & redhat.java from the VS Code
      Marketplace (auto-selects platform-correct variant) instead of using
      x64-only VSIX files from the ISO.
    ● AdvantageScope — Downloads ARM64-native Electron build from GitHub releases.
    ● roboRIO Toolchain — Uses x64 binaries under Prism emulation (no ARM64 host
      build exists; GCC/Binutils do not support Windows ARM64 as a host platform).
    ● Desktop Tools — Native C++ tools (Glass, SysId, DataLogTool, OutlineViewer)
      run under Prism emulation. Pure Java tools (Shuffleboard, PathWeaver,
      RobotBuilder, SmartDashboard) run on whatever JDK is installed.
    ● Elastic Dashboard — x64 Flutter app, runs under Prism emulation
      (no ARM64 build; Flutter Windows ARM64 support is still maturing).

    Windows 11's Prism x86_64 emulator handles ALL x64 components transparently.
    The emulation overhead is ~20-50% depending on workload type.

.PARAMETER WPILibYear
    The FRC season year. Default: 2026

.PARAMETER WPILibVersion
    The WPILib release version. Default: 2026.2.1

.PARAMETER InstallDir
    Base installation directory. Default: C:\Users\Public\wpilib

.PARAMETER DownloadDir
    Temporary directory for downloads. Default: $env:TEMP\WPILibFrankenCode

.PARAMETER SkipDownload
    Skip ISO download if it already exists at the expected path.

.PARAMETER SkipDesktopTools
    Skip installation of desktop tools (Shuffleboard, Glass, etc.)

.PARAMETER SkipCopilotCLI
    Skip Copilot CLI extension setup.

.PARAMETER UseArm64Jdk
    Download and install Microsoft OpenJDK 17 ARM64 instead of using the x64 JDK
    from the ISO. This gives native-speed Java compilation and Gradle builds, but
    BREAKS SIMULATION AND UNIT TESTS that use WPILib's JNI native libraries.

    See KNOWN LIMITATIONS for the full tradeoff.

    Only recommended for Java-only teams that do NOT use simulation or JNI-dependent
    unit tests on this machine (e.g., you deploy directly to a roboRIO and test there).

.PARAMETER SkipAdvantageScopeArm64
    Skip downloading ARM64 AdvantageScope (use the x64 version from ISO under emulation).

.PARAMETER Force
    Overwrite existing installation without prompting.

.EXAMPLE
    .\Install-WPILibFrankenCode-ARM64.ps1
    # Default: x64 JDK under emulation (full compatibility, simulation works)

.EXAMPLE
    .\Install-WPILibFrankenCode-ARM64.ps1 -UseArm64Jdk
    # Native ARM64 JDK (faster builds, but simulation/JNI tests BROKEN)

.EXAMPLE
    .\Install-WPILibFrankenCode-ARM64.ps1 -SkipDesktopTools -SkipCopilotCLI
    # Minimal install — extensions and toolchain only

.NOTES
    Requires: Windows 11 ARM64, Administrator privileges, VS Code installed, internet.
    The x64 WPILib ISO is used as the base — there is no official ARM64 Windows ISO.
    Author:   WPILibFrankenCode Project
    Version:  1.2.0-arm64

    ═══════════════════════════════════════════════════════════════════════════
    KNOWN LIMITATIONS — Read before using on ARM64 Windows
    ═══════════════════════════════════════════════════════════════════════════

    1. JNI ARCHITECTURE MISMATCH (BLOCKER with -UseArm64Jdk)
       ─────────────────────────────────────────────────────
       Java Native Interface (JNI) requires native DLLs to match the JVM's
       architecture EXACTLY. An ARM64 JVM CANNOT load x64 DLLs — this is a
       fundamental JVM constraint, not a WPILib bug.

       WPILib ships x64-only native libraries (wpiHal, ntcore, cscore, wpiutil,
       etc.) in the desktop simulation artifacts. The runtime loader
       (CombinedRuntimeLoader.java) also lacks Windows ARM64 path detection —
       it falls through to the x64 path and then fails with UnsatisfiedLinkError.

       What breaks with -UseArm64Jdk:
         • simulateJava / simulateNative (HAL simulation plugins are x64 DLLs)
         • Unit tests that touch HAL, motor controllers, sensors, or JNI classes
         • Vendor library simulation (CTRE Phoenix, REV, PhotonVision JNI)

       What still works with -UseArm64Jdk:
         • gradlew build (compiles Java, does not load desktop native libs)
         • Deploy to roboRIO (cross-compiles for roboRIO ARM, no desktop JNI)
         • Pure Java unit tests that don't touch WPILib hardware interfaces

       Without -UseArm64Jdk (the DEFAULT), the x64 JDK runs under Prism
       emulation and loads x64 DLLs normally — everything works, just slower.

    2. GRADLE NATIVE C++ DEPENDENCY RESOLUTION (with -UseArm64Jdk)
       ──────────────────────────────────────────────────────────────
       GradleRIO detects the host platform via System.getProperty("os.arch").
       On an ARM64 JDK, this returns "aarch64", causing GradleRIO to resolve
       artifacts with the "windowsarm64" classifier.

       WPILib's OWN windowsarm64 C++ artifacts DO exist on FRC Maven (they
       are cross-compiled from x64 CI runners). However, vendor libraries
       (CTRE Phoenix 6, REV REVLib, PhotonVision, etc.) almost certainly do
       NOT publish windowsarm64 native artifacts. This can cause:
         • Gradle resolution failures for vendor native dependencies
         • Link errors for C++ desktop builds

       The x64 JDK (default) avoids this entirely — os.arch reports "amd64"
       and all dependencies resolve with the standard "windowsx86-64" classifier.

    3. NO OFFICIAL WPILIB SUPPORT (tracked for 2027)
       ───────────────────────────────────────────────
       WPILib's official system requirements state:
         "64-bit Windows 10 or 11 (Arm and 32-bit are not supported)"

       This is tracked in allwpilib issue #3165, assigned to the 2027 milestone.
       The primary blockers for official support are:

       a) JavaFX — Shuffleboard, PathWeaver, SysId, DataLogTool, and RobotBuilder
          all require JavaFX, which has limited Windows ARM64 availability.
          These JavaFX tools are being REMOVED in the 2027 WPILib release,
          eliminating this blocker.

       b) roboRIO cross-compiler — GCC/Binutils do not support Windows ARM64 as
          a host platform (opensdk issue #66). The x64 cross-compiler works fine
          under Prism emulation. A Clang-based toolchain is being considered.

       c) Gradle C++ plugin — Gradle's native C++ plugin does not support ARM64
          Windows hosts. WPILib developer ThadHouse noted: "Arm64 will likely be
          Java and Python only for a while." C++ desktop builds require the
          x64 JDK + emulation.

    4. WHY MACOS ARM64 IS SUPPORTED BUT WINDOWS ARM64 IS NOT
       ─────────────────────────────────────────────────────────
       Apple's toolchain provides trivial cross-compilation from Intel Macs
       via '-target arm64-apple-macos11'. Apple Silicon rapidly became the
       majority Mac platform, creating urgent demand. JavaFX has mature ARM64
       builds for macOS (via Azul/GluonHQ). GitHub Actions got macOS ARM64
       CI runners earlier. None of these advantages existed for Windows ARM64
       until recently. The WPILib dev team also noted they had no Windows ARM64
       test hardware until 2025.

    5. NI TOOLS AND DRIVER STATION (UNTESTED)
       ──────────────────────────────────────────
       The FRC Driver Station and NI roboRIO Imaging Tool are x64 applications.
       User-mode x64 apps run fine under Prism emulation. However, NI tools
       install kernel-mode USB drivers for roboRIO communication, and kernel
       drivers CANNOT be emulated — they must be ARM64-native. If NI's USB
       drivers are x64-only, roboRIO USB communication may fail on ARM64.
       Network-based communication (deploy over WiFi/Ethernet) is unaffected.
       One community member reported the Driver Station worked on Windows 11
       ARM (VMware Fusion on M1 Mac, 2022), but thorough testing is lacking.

    6. VENDOR LIBRARY JNI SIMULATION (with -UseArm64Jdk)
       ──────────────────────────────────────────────────────
       Third-party vendor libraries with JNI simulation components (CTRE
       Phoenix 6 phoenix6-sim, REV REVLib, PhotonVision PhotonLib) ship only
       x64 native DLLs for Windows. These fail to load on an ARM64 JVM.
       Pure-Java vendor libraries (PathPlannerLib, AdvantageKit, Limelight
       NetworkTables API) are unaffected.

    7. THINGS THAT WORK PERFECTLY ON ARM64
       ──────────────────────────────────────
         • VS Code ARM64-native (extensions auto-select correct platform)
         • Java code compilation and Gradle builds (deploy to roboRIO)
         • AdvantageScope (ARM64-native Electron build available)
         • Gradle (pure Java, architecture-independent)
         • Maven offline repository (JAR files, architecture-independent)
         • All VSIX extensions except cpptools/redhat.java (pure JavaScript)
         • IntelliSense for C++ (cpptools ARM64 is mature since 2021)
         • Java Language Server (runs on JDK, any architecture)
         • All WPILib command palette commands in VS Code
         • Project creation, template scaffolding, vendor dep management
         • Network-based robot communication (deploy, NetworkTables, SSH)

    ═══════════════════════════════════════════════════════════════════════════
    RECOMMENDATION
    ═══════════════════════════════════════════════════════════════════════════
    Use the DEFAULT configuration (x64 JDK under Prism emulation) unless you
    have a specific reason to use -UseArm64Jdk. The emulation overhead for
    Java builds is ~30-50% — noticeable but not a blocker for development.
    Simulation, unit tests, and vendor JNI all work correctly with x64 JDK.

    Official Windows ARM64 support is expected in WPILib 2027 (allwpilib #3165).
    ═══════════════════════════════════════════════════════════════════════════
#>

#Requires -RunAsAdministrator
#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$WPILibYear = "2026",
    [string]$WPILibVersion = "2026.2.1",
    [string]$InstallDir = "C:\Users\Public\wpilib",
    [string]$DownloadDir = "$env:TEMP\WPILibFrankenCode",
    [switch]$SkipDownload,
    [switch]$SkipDesktopTools,
    [switch]$SkipCopilotCLI,
    [switch]$UseArm64Jdk,
    [switch]$SkipAdvantageScopeArm64,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "Continue"

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

$script:Config = @{
    Year             = $WPILibYear
    Version          = $WPILibVersion
    YearDir          = Join-Path $InstallDir $WPILibYear
    DownloadDir      = $DownloadDir
    IsoUrl           = "https://packages.wpilib.workers.dev/installer/v${WPILibVersion}/Win64/WPILib_Windows-${WPILibVersion}.iso"
    IsoFileName      = "WPILib_Windows-${WPILibVersion}.iso"
    ResourcesZipName = "WPILibInstaller_Windows-${WPILibVersion}-resources.zip"
    ArtifactsZipName = "WPILib_Windows-${WPILibVersion}-artifacts.zip"
    # ARM64-specific: Microsoft Build of OpenJDK 17 for Windows ARM64
    Arm64JdkUrl      = "https://aka.ms/download-jdk/microsoft-jdk-17-windows-aarch64.zip"
    Arm64JdkZipName  = "microsoft-jdk-17-windows-aarch64.zip"
    # JDK 21 for VS Code Java Language Server (required by redhat.java >= 1.30)
    # This is SEPARATE from the build JDK — the LS only needs JRE 21+, no JNI
    # ARM64: native ARM64 JDK 21 is fine here (LS is pure Java, no WPILib JNI)
    Jdk21LsUrl       = "https://aka.ms/download-jdk/microsoft-jdk-21-windows-aarch64.zip"
    Jdk21LsZipName   = "microsoft-jdk-21-windows-aarch64.zip"
    # ARM64-specific: AdvantageScope ARM64 build
    # NOTE: The exact asset filename varies per release — we discover it dynamically
    AdvantageScopeRepo = "Mechanical-Advantage/AdvantageScope"
}

# Track which components are running natively vs under emulation
$script:Arm64Report = @{
    NativeComponents   = [System.Collections.ArrayList]@()
    EmulatedComponents = [System.Collections.ArrayList]@()
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Message, [string]$Status = "INFO")
    $colors = @{
        "INFO"    = "Cyan"
        "OK"      = "Green"
        "WARN"    = "Yellow"
        "ERROR"   = "Red"
        "SKIP"    = "DarkGray"
        "ACTION"  = "Magenta"
        "ARM64"   = "Blue"
    }
    $color = $colors[$Status]
    if (-not $color) { $color = "White" }
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
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

function Write-SectionHeader {
    param([string]$Message)
    Write-Host ""
    Write-Host ("─" * 60) -ForegroundColor DarkCyan
    Write-Host "  $Message" -ForegroundColor White
    Write-Host ("─" * 60) -ForegroundColor DarkCyan
}

function Test-CommandExists {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Test-IsArm64System {
    <#
    .SYNOPSIS
        Detects if the current system is Windows ARM64.
    #>
    # PROCESSOR_ARCHITECTURE reports the native architecture
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { return $true }
    # Fallback: check processor identifier
    if ($env:PROCESSOR_IDENTIFIER -match 'ARMv\d') { return $true }
    # Fallback: WMI query
    try {
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        # Architecture 12 = ARM64
        if ($cpu.Architecture -eq 12) { return $true }
    }
    catch {}
    return $false
}

function Test-IsRunningUnderEmulation {
    <#
    .SYNOPSIS
        Detects if the current PowerShell process is running under x64 emulation on ARM64.
    #>
    if (-not (Test-IsArm64System)) { return $false }
    # If we're on ARM64 but PROCESSOR_ARCHITECTURE reports AMD64, we're emulated
    # PowerShell 5.1 (x64) on ARM64 Windows would report AMD64
    $procArch = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
    if ($procArch -and $procArch.ToString() -ne 'Arm64') { return $true }
    # Alternative check via environment
    if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64' -and
        (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue)) {
        try {
            $buildLabEx = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").BuildLabEx
            if ($buildLabEx -match 'arm64') { return $true }
        }
        catch {}
    }
    return $false
}

function Invoke-DownloadWithProgress {
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$Description = "Downloading"
    )

    Write-Step "$Description → $OutFile" "ACTION"

    # Prefer BITS for large files (shows progress, resumes)
    if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
        try {
            Start-BitsTransfer -Source $Url -Destination $OutFile -DisplayName $Description -Description $Url
            return
        }
        catch {
            Write-Step "BITS transfer failed, falling back to Invoke-WebRequest: $_" "WARN"
        }
    }

    # Fallback: Invoke-WebRequest with progress
    $oldProgress = $ProgressPreference
    $ProgressPreference = "Continue"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    }
    finally {
        $ProgressPreference = $oldProgress
    }
}

function Expand-ArchiveSafe {
    param(
        [string]$Path,
        [string]$DestinationPath,
        [string]$Description = "Extracting"
    )

    Write-Step "${Description}: ${Path} → ${DestinationPath}" "ACTION"

    if (-not (Test-Path $DestinationPath)) {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    }

    # Use .NET ZipFile for better performance on large archives
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($Path, $DestinationPath)
    }
    catch [System.IO.IOException] {
        # Files already exist — extract with overwrite via shell
        Write-Step "Some files exist, extracting with overwrite..." "WARN"
        Expand-Archive -Path $Path -DestinationPath $DestinationPath -Force
    }
}

function Merge-JsonSetting {
    <#
    .SYNOPSIS
        Merges WPILib settings into VS Code settings.json without overwriting existing user settings.
    #>
    param(
        [string]$SettingsPath,
        [hashtable]$NewSettings
    )

    $existing = @{}
    if (Test-Path $SettingsPath) {
        $content = Get-Content $SettingsPath -Raw -ErrorAction SilentlyContinue
        if ($content) {
            try {
                $existing = $content | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            }
            catch {
                # PowerShell 5.1 doesn't have -AsHashtable, use workaround
                $obj = $content | ConvertFrom-Json -ErrorAction Stop
                $existing = @{}
                foreach ($prop in $obj.PSObject.Properties) {
                    $existing[$prop.Name] = $prop.Value
                }
            }
        }
    }

    # Merge new settings (overwrite WPILib-related keys only)
    foreach ($key in $NewSettings.Keys) {
        $existing[$key] = $NewSettings[$key]
    }

    # Ensure parent directory exists
    $parentDir = Split-Path $SettingsPath -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    # Write back with pretty formatting
    $existing | ConvertTo-Json -Depth 10 | Set-Content $SettingsPath -Encoding UTF8
    Write-Step "Updated: $SettingsPath" "OK"
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 0: PREREQUISITES (ARM64-ENHANCED)
# ─────────────────────────────────────────────────────────────────────────────

function Test-Prerequisites {
    Write-Banner "Phase 0: Prerequisite Checks (ARM64)"

    $failed = $false

    # ── ARM64 Detection ──
    $isArm64 = Test-IsArm64System
    if ($isArm64) {
        Write-Step "Windows ARM64 detected" "ARM64"
        $script:IsArm64 = $true
    }
    else {
        Write-Step "WARNING: This system does NOT appear to be ARM64!" "WARN"
        Write-Step "  PROCESSOR_ARCHITECTURE = $env:PROCESSOR_ARCHITECTURE" "WARN"
        Write-Step "  This script is designed for ARM64 — consider using Install-WPILibFrankenCode.ps1 instead" "WARN"
        $response = Read-Host "Continue anyway? (y/N)"
        if ($response -ne "y" -and $response -ne "Y") {
            Write-Step "Aborting — use Install-WPILibFrankenCode.ps1 for x64 systems" "ERROR"
            exit 1
        }
        $script:IsArm64 = $false
    }

    # ── Check if PowerShell is emulated ──
    if (Test-IsRunningUnderEmulation) {
        Write-Step "PowerShell is running under x64 emulation (normal for PS 5.1 on ARM64)" "ARM64"
        Write-Step "  The installer itself works fine under emulation" "INFO"
    }
    else {
        Write-Step "PowerShell running natively" "ARM64"
    }

    # ── Check Prism emulation availability ──
    if ($isArm64) {
        # On ARM64, x64 apps should be supported by Windows 11's Prism emulator
        $osVersion = [System.Environment]::OSVersion.Version
        if ($osVersion.Build -ge 22000) {
            Write-Step "Windows 11 (Build $($osVersion.Build)) — Prism x64 emulation available" "ARM64"
        }
        else {
            Write-Step "Windows build $($osVersion.Build) — x64 emulation may not be available" "WARN"
            Write-Step "  Windows 11 (Build 22000+) required for reliable x64 emulation" "WARN"
        }
    }

    # Check VS Code
    if (Test-CommandExists "code") {
        $codeVersion = (code --version | Select-Object -First 1).Trim()
        Write-Step "VS Code found: v$codeVersion" "OK"

        # Detect if VS Code is ARM64 native
        $codeExePath = (Get-Command "code" -ErrorAction SilentlyContinue).Source
        if ($codeExePath) {
            # Resolve the actual code.exe (not the batch wrapper)
            $codeBinDir = Split-Path $codeExePath -Parent
            $codeExe = Get-ChildItem (Split-Path $codeBinDir -Parent) -Filter "Code.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($codeExe) {
                try {
                    # Check PE header for architecture
                    $bytes = [System.IO.File]::ReadAllBytes($codeExe.FullName)
                    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
                    $machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
                    # 0xAA64 = ARM64, 0x8664 = AMD64, 0x14C = i386
                    switch ($machine) {
                        0xAA64 {
                            Write-Step "VS Code is ARM64-native — extensions MUST match ARM64" "ARM64"
                            $script:VSCodeIsArm64 = $true
                            $null = $script:Arm64Report.NativeComponents.Add("VS Code (ARM64)")
                        }
                        0x8664 {
                            Write-Step "VS Code is x64 (running under emulation on ARM64)" "WARN"
                            Write-Step "  Consider installing VS Code ARM64 for better performance" "WARN"
                            $script:VSCodeIsArm64 = $false
                            $null = $script:Arm64Report.EmulatedComponents.Add("VS Code (x64 emulated)")
                        }
                        default {
                            Write-Step "VS Code architecture: unknown (machine=$machine)" "WARN"
                            $script:VSCodeIsArm64 = $null
                        }
                    }
                }
                catch {
                    Write-Step "Could not determine VS Code architecture: $_" "WARN"
                    $script:VSCodeIsArm64 = $null
                }
            }
        }
    }
    else {
        Write-Step "VS Code (code) not found on PATH" "ERROR"
        $failed = $true
    }

    # Check admin
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Step "Running as Administrator" "OK"
    }
    else {
        Write-Step "Administrator privileges required" "ERROR"
        $failed = $true
    }

    # Check disk space (need ~6GB for download + extraction + ARM64 JDK)
    $drive = (Split-Path $script:Config.YearDir -Qualifier)
    $freeGB = [math]::Round((Get-PSDrive ($drive -replace ":","")).Free / 1GB, 1)
    if ($freeGB -ge 6) {
        Write-Step "Disk space: ${freeGB}GB free on $drive (need ~6GB for ARM64 install)" "OK"
    }
    else {
        Write-Step "Insufficient disk space: ${freeGB}GB free, need ~6GB on $drive" "ERROR"
        $failed = $true
    }

    # Check network connectivity (required for ARM64 — need additional downloads)
    try {
        $null = Invoke-WebRequest -Uri "https://packages.wpilib.workers.dev" -Method Head -UseBasicParsing -TimeoutSec 10
        Write-Step "Network connectivity to WPILib CDN: OK" "OK"
    }
    catch {
        Write-Step "Cannot reach WPILib CDN (packages.wpilib.workers.dev)" "WARN"
        if (-not $SkipDownload) {
            Write-Step "Use -SkipDownload if ISO is already downloaded" "WARN"
        }
    }

    # ARM64 JDK download connectivity check (only if user opted in)
    if ($UseArm64Jdk) {
        Write-Step "WARNING: -UseArm64Jdk flag detected" "WARN"
        Write-Step "  Simulation (simulateJava) and JNI-based unit tests will NOT work" "WARN"
        Write-Step "  See 'Get-Help .\Install-WPILibFrankenCode-ARM64.ps1 -Full' for details" "WARN"
        try {
            $null = Invoke-WebRequest -Uri "https://aka.ms/download-jdk/microsoft-jdk-17-windows-aarch64.zip" -Method Head -UseBasicParsing -TimeoutSec 10
            Write-Step "Network connectivity to Microsoft JDK CDN: OK" "OK"
        }
        catch {
            Write-Step "Cannot reach Microsoft JDK download — remove -UseArm64Jdk to use x64 JDK under emulation" "WARN"
        }
    }

    # Check git
    if (Test-CommandExists "git") {
        Write-Step "Git found: $(git --version)" "OK"
    }
    else {
        Write-Step "Git not found (optional but recommended)" "WARN"
    }

    # Check existing installation
    if (Test-Path $script:Config.YearDir) {
        if ($Force) {
            Write-Step "Existing install found at $($script:Config.YearDir) — will overwrite (-Force)" "WARN"
        }
        else {
            Write-Step "Existing install found at $($script:Config.YearDir)" "WARN"
            $response = Read-Host "Overwrite? (y/N)"
            if ($response -ne "y" -and $response -ne "Y") {
                Write-Step "Aborting — use -Force to overwrite without prompting" "ERROR"
                exit 1
            }
        }
    }

    if ($failed) {
        Write-Step "Prerequisites not met. Fix the errors above and retry." "ERROR"
        exit 1
    }

    Write-Step "All prerequisites passed" "OK"
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1: DOWNLOAD ISO
# ─────────────────────────────────────────────────────────────────────────────

function Get-WPILibISO {
    Write-Banner "Phase 1: Download WPILib ISO"

    Write-Step "NOTE: WPILib does not provide a Windows ARM64 ISO" "ARM64"
    Write-Step "Using the Win64 (x64) ISO — ARM64-sensitive components will be replaced later" "ARM64"

    $isoPath = Join-Path $script:Config.DownloadDir $script:Config.IsoFileName

    if (-not (Test-Path $script:Config.DownloadDir)) {
        New-Item -ItemType Directory -Path $script:Config.DownloadDir -Force | Out-Null
    }

    if ((Test-Path $isoPath) -and $SkipDownload) {
        Write-Step "ISO already exists, skipping download (-SkipDownload)" "SKIP"
        return $isoPath
    }

    if (Test-Path $isoPath) {
        $fileSize = (Get-Item $isoPath).Length
        # The ISO is approximately 2.4GB
        if ($fileSize -gt 2000000000) {
            Write-Step "ISO already downloaded ($('{0:N1}' -f ($fileSize / 1GB)) GB), skipping" "SKIP"
            return $isoPath
        }
        else {
            Write-Step "Partial/corrupt ISO found ($('{0:N1}' -f ($fileSize / 1MB)) MB), re-downloading" "WARN"
            Remove-Item $isoPath -Force
        }
    }

    Write-Step "Downloading WPILib ISO (~2.4 GB) — this may take a while..." "ACTION"
    Invoke-DownloadWithProgress `
        -Url $script:Config.IsoUrl `
        -OutFile $isoPath `
        -Description "WPILib $($script:Config.Version) ISO (x64)"

    $fileSize = (Get-Item $isoPath).Length
    Write-Step "Downloaded: $('{0:N1}' -f ($fileSize / 1GB)) GB" "OK"

    return $isoPath
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2: MOUNT ISO & EXTRACT ARTIFACTS
# ─────────────────────────────────────────────────────────────────────────────

function Install-FromISO {
    param([string]$IsoPath)

    Write-Banner "Phase 2: Mount ISO & Extract Artifacts"

    # Determine which prefixes to skip
    $skipPrefixes = @("vscode/")  # Always skip bundled VS Code

    # On ARM64, if user opted in to ARM64 JDK, skip extracting the x64 JDK
    if ($UseArm64Jdk) {
        $skipPrefixes += "jdk/"
        Write-Step "Skipping ISO's x64 JDK — will be replaced with ARM64 JDK in Phase 2B" "ARM64"
        Write-Step "  NOTE: This breaks simulation and JNI unit tests (see known limitations)" "WARN"
    }

    $mountResult = $null
    $driveLetter = $null

    try {
        # Mount the ISO
        Write-Step "Mounting ISO: $IsoPath" "ACTION"
        $mountResult = Mount-DiskImage -ImagePath $IsoPath -PassThru
        $driveLetter = ($mountResult | Get-Volume).DriveLetter
        $isoRoot = "${driveLetter}:\"
        Write-Step "ISO mounted at $isoRoot" "OK"

        # List ISO contents
        Write-Step "ISO contents:" "INFO"
        Get-ChildItem $isoRoot | ForEach-Object {
            Write-Step "  $($_.Name) ($('{0:N1}' -f ($_.Length / 1MB)) MB)" "INFO"
        }

        # ── Extract resources zip (config JSONs) ──
        $resourcesZip = Get-ChildItem $isoRoot -Filter "*-resources.zip" | Select-Object -First 1
        if (-not $resourcesZip) {
            throw "Resources zip not found in ISO"
        }

        $resourcesDir = Join-Path $script:Config.DownloadDir "resources"
        if (Test-Path $resourcesDir) { Remove-Item $resourcesDir -Recurse -Force }
        Expand-ArchiveSafe -Path $resourcesZip.FullName -DestinationPath $resourcesDir -Description "Extracting resources (config)"

        # Parse config files
        $script:ResourceConfigs = @{}
        foreach ($jsonFile in (Get-ChildItem $resourcesDir -Filter "*.json")) {
            $configName = $jsonFile.BaseName
            $configData = Get-Content $jsonFile.FullName -Raw | ConvertFrom-Json
            $script:ResourceConfigs[$configName] = $configData
            Write-Step "  Parsed config: ${configName}" "OK"
        }

        # ── Extract main artifacts archive ──
        $artifactsZip = Get-ChildItem $isoRoot -Filter "*-artifacts.zip" | Select-Object -First 1
        if (-not $artifactsZip) {
            throw "Artifacts zip not found in ISO"
        }

        $yearDir = $script:Config.YearDir
        Write-Step "Extracting artifacts (~2+ GB) to $yearDir — this will take several minutes..." "ACTION"
        Write-Step "Skipping prefixes: $($skipPrefixes -join ', ')" "ARM64"

        if (-not (Test-Path $yearDir)) {
            New-Item -ItemType Directory -Path $yearDir -Force | Out-Null
        }

        # For a 2+ GB zip, use .NET directly for better performance
        Write-Step "Extracting (this may take 5-10 minutes)..." "ACTION"
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        $zip = [System.IO.Compression.ZipFile]::OpenRead($artifactsZip.FullName)
        $totalEntries = $zip.Entries.Count
        $extracted = 0
        $skipped = 0
        $lastPercent = -1

        try {
            foreach ($entry in $zip.Entries) {
                $extracted++
                $percent = [math]::Floor(($extracted / $totalEntries) * 100)

                # Progress reporting every 5%
                if ($percent -ne $lastPercent -and ($percent % 5 -eq 0)) {
                    Write-Progress -Activity "Extracting WPILib artifacts" `
                        -Status "$extracted of $totalEntries files ($percent%) — $skipped skipped" `
                        -PercentComplete $percent
                    $lastPercent = $percent
                }

                # Skip prefixes (bundled VS Code, and optionally x64 JDK)
                $skip = $false
                foreach ($prefix in $skipPrefixes) {
                    if ($entry.FullName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                        $skip = $true
                        $skipped++
                        break
                    }
                }
                if ($skip) { continue }

                $destPath = Join-Path $yearDir $entry.FullName

                # Directory entry
                if ($entry.FullName.EndsWith("/")) {
                    if (-not (Test-Path $destPath)) {
                        New-Item -ItemType Directory -Path $destPath -Force | Out-Null
                    }
                    continue
                }

                # File entry — ensure parent dir exists
                $parentDir = Split-Path $destPath -Parent
                if (-not (Test-Path $parentDir)) {
                    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
                }

                # Extract file
                $stream = $entry.Open()
                try {
                    $fileStream = [System.IO.File]::Create($destPath)
                    try {
                        $stream.CopyTo($fileStream)
                    }
                    finally {
                        $fileStream.Close()
                    }
                }
                finally {
                    $stream.Close()
                }
            }
        }
        finally {
            $zip.Dispose()
        }

        Write-Progress -Activity "Extracting WPILib artifacts" -Completed
        Write-Step "Extracted $($extracted - $skipped) files to $yearDir ($skipped skipped for ARM64)" "OK"

        # Verify key directories exist
        $expectedDirs = @("maven", "tools", "roborio", "vsCodeExtensions",
                          "vendordeps", "frccode", "installUtils", "icons")
        # JDK is present from ISO if we are NOT replacing it
        if (-not $UseArm64Jdk) {
            $expectedDirs = @("jdk") + $expectedDirs
        }

        foreach ($dir in $expectedDirs) {
            $dirPath = Join-Path $yearDir $dir
            if (Test-Path $dirPath) {
                Write-Step "  ✓ $dir/" "OK"
            }
            else {
                Write-Step "  ✗ $dir/ — MISSING" "ERROR"
            }
        }

        # Optional directories
        $optionalDirs = @("advantagescope", "elastic", "documentation", "utility")
        foreach ($dir in $optionalDirs) {
            $dirPath = Join-Path $yearDir $dir
            if (Test-Path $dirPath) {
                Write-Step "  ✓ $dir/ (optional)" "OK"
            }
            else {
                Write-Step "  ~ $dir/ not present (optional)" "SKIP"
            }
        }

        # Classify extracted x64 components for the ARM64 report
        $null = $script:Arm64Report.EmulatedComponents.Add("roboRIO GCC cross-compiler (x64 → Prism)")
        $toolsDir = Join-Path $yearDir "tools"
        if (Test-Path $toolsDir) {
            $nativeExes = @(Get-ChildItem $toolsDir -Filter "*.exe" -ErrorAction SilentlyContinue)
            if ($nativeExes.Count -gt 0) {
                $null = $script:Arm64Report.EmulatedComponents.Add("Native desktop tools: Glass, SysId, etc. (x64 → Prism)")
            }
        }
        $elasticDir = Join-Path $yearDir "elastic"
        if (Test-Path $elasticDir) {
            $null = $script:Arm64Report.EmulatedComponents.Add("Elastic Dashboard (x64 Flutter → Prism)")
        }
        $null = $script:Arm64Report.NativeComponents.Add("Maven offline repo (architecture-independent)")
        $null = $script:Arm64Report.NativeComponents.Add("Vendor dependencies (architecture-independent)")
        $null = $script:Arm64Report.NativeComponents.Add("Gradle wrapper (pure Java)")
        $null = $script:Arm64Report.NativeComponents.Add("Java desktop tools: Shuffleboard, PathWeaver, etc. (via ARM64 JDK)")
    }
    finally {
        # Always unmount the ISO
        if ($mountResult) {
            Write-Step "Unmounting ISO..." "ACTION"
            Dismount-DiskImage -ImagePath $IsoPath | Out-Null
            Write-Step "ISO unmounted" "OK"
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2B: ARM64 JDK REPLACEMENT
# ─────────────────────────────────────────────────────────────────────────────

function Install-Arm64Jdk {
    Write-Banner "Phase 2B: ARM64 JDK Installation"

    if (-not $UseArm64Jdk) {
        Write-Step "Using x64 JDK from ISO under Prism emulation (default — simulation compatible)" "OK"
        Write-Step "  Use -UseArm64Jdk for native ARM64 JDK (faster builds, but breaks simulation)" "INFO"
        $null = $script:Arm64Report.EmulatedComponents.Add("JDK 17 (x64 Temurin → Prism emulation — simulation compatible)")
        return
    }

    Write-Step "" "INFO"
    Write-Step "╔══════════════════════════════════════════════════════════════╗" "WARN"
    Write-Step "║  WARNING: ARM64 JDK selected — simulation will NOT work!   ║" "WARN"
    Write-Step "║  JNI requires DLLs to match JVM architecture exactly.      ║" "WARN"
    Write-Step "║  WPILib ships x64-only native DLLs for desktop simulation. ║" "WARN"
    Write-Step "║  Re-run without -UseArm64Jdk if you need simulation.       ║" "WARN"
    Write-Step "╚══════════════════════════════════════════════════════════════╝" "WARN"
    Write-Step "" "INFO"

    $yearDir = $script:Config.YearDir
    $jdkDir = Join-Path $yearDir "jdk"
    $downloadDir = $script:Config.DownloadDir

    Write-Step "Replacing x64 JDK with Microsoft OpenJDK 17 ARM64" "ARM64"
    Write-Step "  Source: $($script:Config.Arm64JdkUrl)" "INFO"

    # Download ARM64 JDK
    $jdkZipPath = Join-Path $downloadDir $script:Config.Arm64JdkZipName
    if (Test-Path $jdkZipPath) {
        $fileSize = (Get-Item $jdkZipPath).Length
        if ($fileSize -gt 100000000) {
            Write-Step "ARM64 JDK zip already downloaded ($('{0:N0}' -f ($fileSize / 1MB)) MB)" "SKIP"
        }
        else {
            Remove-Item $jdkZipPath -Force
            Invoke-DownloadWithProgress -Url $script:Config.Arm64JdkUrl -OutFile $jdkZipPath -Description "Microsoft OpenJDK 17 ARM64"
        }
    }
    else {
        Invoke-DownloadWithProgress -Url $script:Config.Arm64JdkUrl -OutFile $jdkZipPath -Description "Microsoft OpenJDK 17 ARM64"
    }

    # Remove existing x64 JDK if present
    if (Test-Path $jdkDir) {
        Write-Step "Removing x64 JDK at: $jdkDir" "ACTION"
        Remove-Item $jdkDir -Recurse -Force
    }

    # Extract ARM64 JDK
    $tempExtract = Join-Path $downloadDir "jdk-arm64-temp"
    if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }
    Expand-ArchiveSafe -Path $jdkZipPath -DestinationPath $tempExtract -Description "Extracting ARM64 JDK"

    # The Microsoft JDK zip extracts to a directory like "jdk-17.0.18+11"
    # We need to move it to the expected "jdk" directory
    $extractedJdkDir = Get-ChildItem $tempExtract -Directory | Where-Object { $_.Name -match "jdk" } | Select-Object -First 1
    if (-not $extractedJdkDir) {
        throw "Could not find JDK directory in extracted ARM64 JDK archive"
    }

    Write-Step "Moving ARM64 JDK: $($extractedJdkDir.Name) → jdk/" "ACTION"
    Move-Item $extractedJdkDir.FullName $jdkDir -Force

    # Cleanup temp
    Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

    # Verify
    $javaExe = Join-Path $jdkDir "bin\java.exe"
    if (Test-Path $javaExe) {
        $javaVersion = & $javaExe -version 2>&1 | Select-Object -First 1
        Write-Step "ARM64 JDK installed: $javaVersion" "OK"

        # Verify it's actually ARM64
        try {
            $bytes = [System.IO.File]::ReadAllBytes($javaExe)
            $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
            $machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
            if ($machine -eq 0xAA64) {
                Write-Step "Confirmed: java.exe is ARM64-native" "ARM64"
                $null = $script:Arm64Report.NativeComponents.Add("JDK 17 (Microsoft OpenJDK ARM64)")
            }
            else {
                Write-Step "Warning: java.exe does not appear to be ARM64 (machine=0x$($machine.ToString('X4')))" "WARN"
                $null = $script:Arm64Report.EmulatedComponents.Add("JDK 17 (architecture unclear)")
            }
        }
        catch {
            Write-Step "Could not verify JDK architecture: $_" "WARN"
        }
    }
    else {
        Write-Step "ARM64 JDK installation may have failed — java.exe not found at $javaExe" "ERROR"
        Write-Step "Check $jdkDir for extracted contents" "ERROR"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2C: ARM64 ADVANTAGESCOPE (OPTIONAL)
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2D: JDK 21 FOR VS CODE JAVA LANGUAGE SERVER
# ─────────────────────────────────────────────────────────────────────────────

function Install-Jdk21LanguageServer {
    Write-Banner "Phase 2D: JDK 21 Language Server Installation"

    # Why a second JDK?
    #   redhat.java (VS Code Java extension) >= v1.30 requires JDK 21+ to LAUNCH
    #   its embedded language server (Eclipse JDT-LS). This is separate from the
    #   JDK used to BUILD robot code — WPILib Gradle still targets JDK 17.
    #
    #   java.jdt.ls.java.home → JDK 21  (starts the IntelliSense daemon)
    #   java.configuration.runtimes → JDK 17 as default (compiles robot code)
    #   JAVA_HOME / terminal PATH    → JDK 17 (Gradle build path, unchanged)
    #
    #   On ARM64, using an ARM64-native JDK 21 for the LS is safe: the language
    #   server is pure Java and never loads WPILib JNI native DLLs.

    $yearDir     = $script:Config.YearDir
    $jdk21LsPath = Join-Path $yearDir "jdk21ls"
    $downloadDir = $script:Config.DownloadDir

    # Check if already installed and valid
    $jdk21Exe = Join-Path $jdk21LsPath "bin\java.exe"
    if ((Test-Path $jdk21Exe) -and -not $Force) {
        $ver = (& $jdk21Exe -version 2>&1 | Select-Object -First 1) -replace '"', ''
        if ($ver -match '2[1-9]\.|[3-9]\d\.') {
            Write-Step "JDK 21 LS already installed: $ver" "SKIP"
            $null = $script:Arm64Report.NativeComponents.Add("JDK 21 LS (Microsoft OpenJDK ARM64 — language server only)")
            return
        }
    }

    Write-Step "Downloading Microsoft JDK 21 ARM64 for VS Code language server" "ARM64"
    Write-Step "  NOTE: ARM64-native JDK 21 is safe for the LS — no WPILib JNI involved" "INFO"
    Write-Step "  JDK 17 (builds + simulation) is unchanged" "INFO"

    $jdk21ZipPath = Join-Path $downloadDir $script:Config.Jdk21LsZipName
    $needDownload = $true
    if ((Test-Path $jdk21ZipPath) -and -not $Force) {
        $sz = (Get-Item $jdk21ZipPath).Length
        if ($sz -gt 100MB) {
            Write-Step "JDK 21 zip already cached ($('{0:N0}' -f ($sz/1MB)) MB) — reusing" "SKIP"
            $needDownload = $false
        } else {
            Remove-Item $jdk21ZipPath -Force
        }
    }
    if ($needDownload) {
        Invoke-DownloadWithProgress -Url $script:Config.Jdk21LsUrl -OutFile $jdk21ZipPath -Description "Microsoft JDK 21 ARM64 (language server)"
    }

    # Clean and extract
    if (Test-Path $jdk21LsPath) { Remove-Item $jdk21LsPath -Recurse -Force }
    $tempDir = Join-Path $downloadDir "jdk21ls-temp"
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }

    Expand-ArchiveSafe -Path $jdk21ZipPath -DestinationPath $tempDir -Description "Extracting JDK 21 LS"

    $extracted = Get-ChildItem $tempDir -Directory | Select-Object -First 1
    if (-not $extracted) { throw "Could not find JDK directory in extracted JDK 21 archive" }

    Write-Step "Moving $($extracted.Name) → jdk21ls/" "ACTION"
    Move-Item $extracted.FullName $jdk21LsPath -Force
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

    # Verify
    if (-not (Test-Path $jdk21Exe)) {
        throw "JDK 21 LS installation failed — java.exe not found at $jdk21Exe"
    }
    $ver = (& $jdk21Exe -version 2>&1 | Select-Object -First 1) -replace '"', ''
    Write-Step "JDK 21 LS installed: $ver" "OK"

    # Verify ARM64-native
    try {
        $bytes    = [System.IO.File]::ReadAllBytes($jdk21Exe)
        $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
        $machine  = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
        if ($machine -eq 0xAA64) {
            Write-Step "Confirmed: jdk21ls/bin/java.exe is ARM64-native" "ARM64"
            $null = $script:Arm64Report.NativeComponents.Add("JDK 21 LS (Microsoft OpenJDK ARM64 — language server only)")
        } else {
            Write-Step "JDK 21 LS architecture: 0x$($machine.ToString('X4'))" "WARN"
        }
    } catch {
        Write-Step "Could not verify JDK 21 LS architecture: $_" "WARN"
    }
}

function Install-Arm64AdvantageScope {
    Write-Banner "Phase 2C: ARM64 AdvantageScope"

    if ($SkipAdvantageScopeArm64) {
        Write-Step "Skipping ARM64 AdvantageScope (-SkipAdvantageScopeArm64)" "SKIP"
        Write-Step "The x64 AdvantageScope from the ISO will run under Prism emulation" "INFO"
        return
    }

    $yearDir = $script:Config.YearDir
    $asDir = Join-Path $yearDir "advantagescope"

    if (-not (Test-Path $asDir)) {
        Write-Step "AdvantageScope directory not found — may not have been in ISO" "SKIP"
        return
    }

    Write-Step "Attempting to replace x64 AdvantageScope with ARM64 build" "ARM64"

    # Try to find the ARM64 release via GitHub API
    try {
        $releasesUrl = "https://api.github.com/repos/$($script:Config.AdvantageScopeRepo)/releases/latest"
        $headers = @{ "Accept" = "application/vnd.github.v3+json" }

        # Use gh if available for authenticated requests (higher rate limit)
        $releaseData = $null
        if (Test-CommandExists "gh") {
            try {
                $releaseJson = gh api "repos/$($script:Config.AdvantageScopeRepo)/releases/latest" 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $releaseData = $releaseJson | ConvertFrom-Json
                }
            }
            catch {}
        }

        if (-not $releaseData) {
            $releaseData = Invoke-RestMethod -Uri $releasesUrl -Headers $headers -UseBasicParsing
        }

        Write-Step "Latest AdvantageScope release: $($releaseData.tag_name)" "INFO"

        # Look for ARM64 Windows asset
        $arm64Asset = $null
        foreach ($asset in $releaseData.assets) {
            if ($asset.name -match "win.*arm64" -and $asset.name -match "\.(exe|zip)$") {
                $arm64Asset = $asset
                break
            }
        }

        if (-not $arm64Asset) {
            # Try alternate naming patterns
            foreach ($asset in $releaseData.assets) {
                if ($asset.name -match "arm64.*win" -and $asset.name -match "\.(exe|zip)$") {
                    $arm64Asset = $asset
                    break
                }
            }
        }

        if ($arm64Asset) {
            Write-Step "Found ARM64 asset: $($arm64Asset.name) ($('{0:N1}' -f ($arm64Asset.size / 1MB)) MB)" "OK"

            $asDownloadPath = Join-Path $script:Config.DownloadDir $arm64Asset.name

            Invoke-DownloadWithProgress -Url $arm64Asset.browser_download_url -OutFile $asDownloadPath -Description "AdvantageScope ARM64"

            if ($arm64Asset.name -match "\.zip$") {
                # Replace the x64 AdvantageScope directory
                Write-Step "Replacing x64 AdvantageScope with ARM64 build..." "ACTION"
                Remove-Item $asDir -Recurse -Force
                Expand-ArchiveSafe -Path $asDownloadPath -DestinationPath $asDir -Description "Extracting ARM64 AdvantageScope"
                Write-Step "ARM64 AdvantageScope installed" "OK"
                $null = $script:Arm64Report.NativeComponents.Add("AdvantageScope (ARM64)")
            }
            elseif ($arm64Asset.name -match "\.exe$") {
                # It's an installer EXE — copy it, but note user may need to run it
                Write-Step "ARM64 AdvantageScope is an installer (.exe)" "INFO"
                $asExeDest = Join-Path $asDir "AdvantageScope-ARM64-Setup.exe"
                Copy-Item $asDownloadPath $asExeDest -Force
                Write-Step "Installer saved to: $asExeDest" "OK"
                Write-Step "You may need to run this installer manually to replace the x64 version" "WARN"
                $null = $script:Arm64Report.NativeComponents.Add("AdvantageScope (ARM64 installer available)")
            }
        }
        else {
            Write-Step "No ARM64 Windows asset found in latest AdvantageScope release" "WARN"
            Write-Step "Available assets:" "INFO"
            foreach ($asset in $releaseData.assets) {
                Write-Step "  $($asset.name)" "INFO"
            }
            Write-Step "x64 AdvantageScope will run under Prism emulation" "INFO"
            $null = $script:Arm64Report.EmulatedComponents.Add("AdvantageScope (x64 → Prism, no ARM64 build found)")
        }
    }
    catch {
        Write-Step "Could not check AdvantageScope releases: $_" "WARN"
        Write-Step "x64 AdvantageScope from ISO will run under Prism emulation" "INFO"
        $null = $script:Arm64Report.EmulatedComponents.Add("AdvantageScope (x64 → Prism)")
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 3: GRADLE CACHE SETUP
# ─────────────────────────────────────────────────────────────────────────────

function Install-GradleCache {
    Write-Banner "Phase 3: Gradle Wrapper Cache"

    $yearDir = $script:Config.YearDir
    $installUtils = Join-Path $yearDir "installUtils"

    # Find the gradle zip
    $gradleZip = Get-ChildItem $installUtils -Filter "gradle-*-bin.zip" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $gradleZip) {
        Write-Step "Gradle wrapper zip not found in installUtils/ — skipping" "WARN"
        return
    }

    Write-Step "Found: $($gradleZip.Name)" "OK"
    Write-Step "Gradle is pure Java — runs natively on ARM64 JDK" "ARM64"

    # Try to get the hash from config, otherwise compute it
    $gradleHash = $null
    if ($script:ResourceConfigs -and $script:ResourceConfigs.ContainsKey("fullConfig")) {
        $fc = $script:ResourceConfigs["fullConfig"]
        if ($fc.Gradle -and $fc.Gradle.Hash) {
            $gradleHash = $fc.Gradle.Hash
            Write-Step "Gradle hash from config: $gradleHash" "INFO"
        }
    }

    if (-not $gradleHash) {
        $gradleHash = "generated"
        Write-Step "No hash in config, using placeholder directory" "WARN"
    }

    $gradleName = [System.IO.Path]::GetFileNameWithoutExtension($gradleZip.Name) -replace "-bin$", ""
    $gradleDistName = $gradleZip.Name -replace "\.zip$", ""

    $gradleDirs = @(
        (Join-Path $env:USERPROFILE ".gradle\wrapper\dists\$gradleDistName\$gradleHash"),
        (Join-Path $env:USERPROFILE ".gradle\permwrapper\dists\$gradleDistName\$gradleHash")
    )

    foreach ($dir in $gradleDirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $destFile = Join-Path $dir $gradleZip.Name
        Copy-Item $gradleZip.FullName $destFile -Force
        Write-Step "Cached: $destFile" "OK"

        # Also extract to adjacent directory for immediate availability
        $extractDir = Join-Path $dir $gradleName
        if (-not (Test-Path $extractDir)) {
            Expand-ArchiveSafe -Path $destFile -DestinationPath $dir -Description "Pre-extracting Gradle"
        }

        # Create the marker file that tells Gradle wrapper the zip is valid
        $markerFile = Join-Path $dir "$gradleDistName.zip.ok"
        "" | Set-Content $markerFile -NoNewline
        Write-Step "Created marker: $($gradleDistName).zip.ok" "OK"
    }

    Write-Step "Gradle wrapper cache configured" "OK"
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 4: TOOL & MAVEN POST-SETUP
# ─────────────────────────────────────────────────────────────────────────────

function Install-ToolsAndMaven {
    Write-Banner "Phase 4: Tools & Maven Post-Setup"

    $yearDir = $script:Config.YearDir
    $javaExe = Join-Path $yearDir "jdk\bin\java.exe"

    # Verify JDK is present
    if (-not (Test-Path $javaExe)) {
        Write-Step "JDK not found at: $javaExe" "ERROR"
        Write-Step "Cannot run post-installation tools without JDK" "ERROR"
        return
    }

    # Test JDK
    $javaVersion = & $javaExe -version 2>&1 | Select-Object -First 1
    Write-Step "JDK: $javaVersion" "OK"

    # ── Run ToolsUpdater ──
    $toolsUpdater = Join-Path $yearDir "tools\ToolsUpdater.jar"
    if (Test-Path $toolsUpdater) {
        Write-Step "Running ToolsUpdater.jar (via ARM64 JDK)..." "ACTION"
        try {
            $env:JAVA_HOME = Join-Path $yearDir "jdk"
            $output = & $javaExe -jar $toolsUpdater 2>&1
            $output | ForEach-Object { Write-Step "  $_" "INFO" }
            Write-Step "ToolsUpdater completed" "OK"
        }
        catch {
            Write-Step "ToolsUpdater failed: $_" "WARN"
            Write-Step "Desktop tools may not have proper launchers" "WARN"
        }
    }
    else {
        Write-Step "ToolsUpdater.jar not found — skipping" "SKIP"
    }

    # ── Run MavenMetaDataFixer ──
    $mavenFixer = Join-Path $yearDir "maven\MavenMetaDataFixer.jar"
    if (Test-Path $mavenFixer) {
        Write-Step "Running MavenMetaDataFixer.jar (via ARM64 JDK)..." "ACTION"
        try {
            Push-Location (Join-Path $yearDir "maven")
            $output = & $javaExe -jar $mavenFixer 2>&1
            $output | ForEach-Object { Write-Step "  $_" "INFO" }
            Pop-Location
            Write-Step "MavenMetaDataFixer completed" "OK"
        }
        catch {
            Write-Step "MavenMetaDataFixer failed: $_" "WARN"
            Write-Step "Offline Maven repository may have stale metadata" "WARN"
            Pop-Location -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Step "MavenMetaDataFixer.jar not found — skipping" "SKIP"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 5: VS CODE EXTENSION INSTALLATION (ARM64-AWARE)
# ─────────────────────────────────────────────────────────────────────────────

function Install-VSCodeExtensions {
    Write-Banner "Phase 5: VS Code Extension Installation (ARM64)"

    $yearDir = $script:Config.YearDir
    $vsixDir = Join-Path $yearDir "vsCodeExtensions"

    if (-not (Test-Path $vsixDir)) {
        Write-Step "VSIX directory not found: $vsixDir" "ERROR"
        return
    }

    # Get all VSIX files from the ISO
    $vsixFiles = Get-ChildItem $vsixDir -Filter "*.vsix"
    Write-Step "Found $($vsixFiles.Count) VSIX files in ISO:" "INFO"
    foreach ($vsix in $vsixFiles) {
        Write-Step "  $($vsix.Name) ($('{0:N1}' -f ($vsix.Length / 1MB)) MB)" "INFO"
    }

    # ── ARM64-critical: Identify extensions that need platform-specific builds ──
    # These extensions contain native binaries that MUST match VS Code's architecture
    $platformSpecificExtensions = @(
        "cpptools",     # ms-vscode.cpptools — IntelliSense engine is native
        "java-1"        # redhat.java — JDT Language Server has platform components
    )

    Write-Step "" "INFO"
    Write-Step "ARM64 Extension Strategy:" "ARM64"
    Write-Step "  Extensions with native binaries (cpptools, redhat.java):" "ARM64"
    Write-Step "    → Install from VS Code Marketplace (auto-selects ARM64 variant)" "ARM64"
    Write-Step "  Pure JavaScript extensions (wpilib, java-debug, java-dependency):" "ARM64"
    Write-Step "    → Install from ISO VSIX (architecture-independent)" "ARM64"
    Write-Step "" "INFO"

    # Get currently installed extensions
    $installedExtensions = @(code --list-extensions 2>$null)
    Write-Step "Currently installed extensions: $($installedExtensions.Count)" "INFO"

    $installedCount = 0
    $failedCount = 0

    # ── Step 1: Install platform-specific extensions from Marketplace ──

    Write-SectionHeader "Installing platform-specific extensions from Marketplace"

    $marketplaceExtensions = @(
        @{ Id = "ms-vscode.cpptools"; Name = "C/C++ (cpptools)" },
        @{ Id = "redhat.java"; Name = "Java Language Support" }
    )

    foreach ($ext in $marketplaceExtensions) {
        Write-Step "Installing $($ext.Name) from Marketplace (ARM64-aware)..." "ACTION"
        try {
            $output = & code --install-extension $ext.Id --force 2>&1
            $outputStr = ($output | Out-String)
            $output | ForEach-Object { Write-Step "  $_" "INFO" }

            if ($outputStr -match "restart VS Code") {
                Write-Step "Extension locked — already installed, will activate after restart" "WARN"
                $installedCount++
            }
            elseif ($outputStr -match "successfully installed|was successfully installed") {
                $installedCount++
                Write-Step "Installed from Marketplace: $($ext.Id)" "OK"
                $null = $script:Arm64Report.NativeComponents.Add("Extension: $($ext.Id) (Marketplace ARM64)")
            }
            else {
                $installedCount++
                Write-Step "Installed: $($ext.Id)" "OK"
            }
        }
        catch {
            Write-Step "Failed to install $($ext.Id) from Marketplace: $_" "ERROR"
            Write-Step "Falling back to ISO VSIX (may not work on ARM64 VS Code)..." "WARN"

            # Try the VSIX from the ISO as fallback
            $fallbackVsix = $vsixFiles | Where-Object { $_.Name -match $ext.Id.Split('.')[-1] } | Select-Object -First 1
            if ($fallbackVsix) {
                try {
                    $output = & code --install-extension $fallbackVsix.FullName --force 2>&1
                    $output | ForEach-Object { Write-Step "  $_" "INFO" }
                    $installedCount++
                    Write-Step "Installed from ISO (x64 — may not work on ARM64 VS Code): $($fallbackVsix.Name)" "WARN"
                    $null = $script:Arm64Report.EmulatedComponents.Add("Extension: $($ext.Id) (x64 VSIX fallback)")
                }
                catch {
                    Write-Step "Fallback VSIX also failed: $_" "ERROR"
                    $failedCount++
                }
            }
            else {
                $failedCount++
            }
        }
    }

    # ── Step 2: Install architecture-independent extensions from ISO VSIX ──

    Write-SectionHeader "Installing architecture-independent extensions from ISO"

    # Define install order for the remaining VSIX files
    $isoInstallOrder = @(
        "*java-debug*",
        "*java-dependency*",
        "*wpilib*"           # WPILib extension last (depends on others)
    )

    # Exclude VSIX files for extensions we already installed from Marketplace
    $remainingVsix = $vsixFiles | Where-Object {
        $name = $_.Name
        $isPlatformSpecific = $false
        foreach ($pse in $platformSpecificExtensions) {
            if ($name -match $pse) {
                $isPlatformSpecific = $true
                break
            }
        }
        -not $isPlatformSpecific
    }

    foreach ($pattern in $isoInstallOrder) {
        $matchingVsix = $remainingVsix | Where-Object { $_.Name -like $pattern } | Select-Object -First 1
        if (-not $matchingVsix) {
            $matchingVsix = $remainingVsix | Where-Object { $_.Name -like "*$($pattern.Trim('*'))*" } | Select-Object -First 1
        }
        if (-not $matchingVsix) { continue }

        Write-Step "Installing: $($matchingVsix.Name)..." "ACTION"
        try {
            $output = & code --install-extension $matchingVsix.FullName --force 2>&1
            $outputStr = ($output | Out-String)
            $output | ForEach-Object { Write-Step "  $_" "INFO" }

            if ($outputStr -match "restart VS Code") {
                Write-Step "Extension locked — already installed, will activate after restart" "WARN"
                $installedCount++
            }
            elseif ($outputStr -match "successfully installed") {
                $installedCount++
                Write-Step "Installed: $($matchingVsix.Name)" "OK"
            }
            else {
                $installedCount++
                Write-Step "Installed: $($matchingVsix.Name)" "OK"
            }
        }
        catch {
            Write-Step "Failed to install $($matchingVsix.Name): $_" "ERROR"
            $failedCount++
        }

        # Remove from list so we don't double-install
        $remainingVsix = $remainingVsix | Where-Object { $_.FullName -ne $matchingVsix.FullName }
    }

    # Install any remaining VSIX files not caught by ordered patterns
    foreach ($vsix in $remainingVsix) {
        Write-Step "Installing (additional): $($vsix.Name)..." "ACTION"
        try {
            $output = & code --install-extension $vsix.FullName --force 2>&1
            $output | ForEach-Object { Write-Step "  $_" "INFO" }
            $installedCount++
            Write-Step "Installed: $($vsix.Name)" "OK"
        }
        catch {
            Write-Step "Failed to install $($vsix.Name): $_" "ERROR"
            $failedCount++
        }
    }

    Write-Step "Extensions installed: $installedCount, failed: $failedCount" $(if ($failedCount -gt 0) { "WARN" } else { "OK" })

    # Verify
    Write-Step "Verifying installed extensions..." "ACTION"
    $finalExtensions = @(code --list-extensions 2>$null)
    $wplibExt = $finalExtensions | Where-Object { $_ -like "*wpilib*" }
    if ($wplibExt) {
        Write-Step "WPILib extension verified: $wplibExt" "OK"
    }
    else {
        Write-Step "WPILib extension NOT found in installed extensions list!" "ERROR"
        Write-Step "Installed extensions:" "INFO"
        $finalExtensions | ForEach-Object { Write-Step "  $_" "INFO" }
    }

    $null = $script:Arm64Report.NativeComponents.Add("Extension: wpilibsuite.vscode-wpilib (pure JS)")
    $null = $script:Arm64Report.NativeComponents.Add("Extension: vscjava.vscode-java-debug (pure JS)")
    $null = $script:Arm64Report.NativeComponents.Add("Extension: vscjava.vscode-java-dependency (pure JS)")
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 6: VS CODE SETTINGS CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

function Set-VSCodeSettings {
    Write-Banner "Phase 6: VS Code Settings Configuration"

    $yearDir     = $script:Config.YearDir
    $jdkPath     = Join-Path $yearDir "jdk"       # JDK 17 — WPILib builds & Gradle
    $jdk21LsPath = Join-Path $yearDir "jdk21ls"   # JDK 21 — VS Code language server

    $settingsPath = Join-Path $env:APPDATA "Code\User\settings.json"

    Write-Step "Target settings file: $settingsPath" "INFO"

    # Two-JDK strategy:
    #   java.jdt.ls.java.home          → JDK 21  (language server requires 21+)
    #   java.configuration.runtimes    → JDK 17 default (robot code compile target)
    #                                  + JDK 21 listed (available for project override)
    #   JAVA_HOME / terminal PATH      → JDK 17  (Gradle build JDK, unchanged)
    $wpilibSettings = @{
        "java.jdt.ls.java.home"       = $jdk21LsPath
        "java.configuration.runtimes" = @(
            @{
                "name"    = "JavaSE-17"
                "path"    = $jdkPath
                "default" = $true
            },
            @{
                "name"    = "JavaSE-21"
                "path"    = $jdk21LsPath
                "default" = $false
            }
        )
        "terminal.integrated.env.windows" = @{
            "JAVA_HOME" = $jdkPath
            "PATH"      = "$jdkPath\bin;`${env:PATH}"
        }
    }

    Merge-JsonSetting -SettingsPath $settingsPath -NewSettings $wpilibSettings

    Write-Step "VS Code settings configured for WPILib" "OK"
    Write-Step "  java.jdt.ls.java.home → $jdk21LsPath (JDK 21 — language server)" "INFO"
    Write-Step "  java.configuration.runtimes[JavaSE-17] → $jdkPath (default, WPILib builds)" "INFO"
    Write-Step "  java.configuration.runtimes[JavaSE-21] → $jdk21LsPath" "INFO"
    Write-Step "  JAVA_HOME → $jdkPath (terminal env, Gradle builds unchanged)" "INFO"
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 7: ENVIRONMENT HELPERS & SHORTCUTS
# ─────────────────────────────────────────────────────────────────────────────

function Install-EnvironmentHelpers {
    Write-Banner "Phase 7: Environment Helpers & Shortcuts"

    $yearDir = $script:Config.YearDir
    $year = $script:Config.Year
    $frcCodeDir = Join-Path $yearDir "frccode"

    # ── Verify/create launcher scripts ──
    if (Test-Path $frcCodeDir) {
        Write-Step "Launcher scripts directory exists: $frcCodeDir" "OK"
        Get-ChildItem $frcCodeDir | ForEach-Object {
            Write-Step "  $($_.Name)" "INFO"
        }
    }
    else {
        Write-Step "Creating launcher scripts..." "ACTION"
        New-Item -ItemType Directory -Path $frcCodeDir -Force | Out-Null

        # Create frcvars PowerShell script
        $frcVarsPs1 = Join-Path $frcCodeDir "frcvars${year}.ps1"
        @"
# WPILib FrankenCode Environment Setup (ARM64)
`$WPILibHome = "$yearDir"
`$env:JAVA_HOME = "`$WPILibHome\jdk"
`$env:PATH = "`$WPILibHome\jdk\bin;`$env:PATH"
Write-Host "WPILib $year environment loaded (FrankenCode ARM64)" -ForegroundColor Green
Write-Host "  JAVA_HOME = `$env:JAVA_HOME" -ForegroundColor Cyan
"@ | Set-Content $frcVarsPs1 -Encoding UTF8
        Write-Step "Created: $frcVarsPs1" "OK"

        # Create frcvars batch script
        $frcVarsBat = Join-Path $frcCodeDir "frcvars${year}.bat"
        @"
@echo off
pushd "%~dp0..\jdk"
set JAVA_HOME=%CD%
set PATH=%CD%\bin;%PATH%
popd
echo WPILib $year environment loaded (FrankenCode ARM64)
"@ | Set-Content $frcVarsBat -Encoding ASCII
        Write-Step "Created: $frcVarsBat" "OK"
    }

    # ── Create a FrankenCode launcher script ──
    $frankenLauncher = Join-Path $frcCodeDir "FrankenCode${year}.cmd"
    @"
@echo off
REM WPILib FrankenCode Launcher (ARM64) — Opens modern VS Code with WPILib environment
call "%~dp0frcvars${year}.bat"
start "" code %*
"@ | Set-Content $frankenLauncher -Encoding ASCII
    Write-Step "Created FrankenCode launcher: $frankenLauncher" "OK"

    # ── Create Desktop Shortcut ──
    try {
        $shell = New-Object -ComObject WScript.Shell
        $desktopPath = [Environment]::GetFolderPath("Desktop")

        # WPILib FrankenCode shortcut
        $shortcutPath = Join-Path $desktopPath "WPILib FrankenCode $year (ARM64).lnk"
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $frankenLauncher
        $shortcut.WorkingDirectory = $frcCodeDir
        $shortcut.Description = "Launch VS Code with WPILib $year environment (ARM64)"
        $iconFile = Join-Path $yearDir "icons\wpilib-256.ico"
        if (Test-Path $iconFile) {
            $shortcut.IconLocation = $iconFile
        }
        $shortcut.Save()
        Write-Step "Desktop shortcut created: $shortcutPath" "OK"

        # ── Create tool shortcuts (if tools exist) ──
        if (-not $SkipDesktopTools) {
            $toolsDir = Join-Path $yearDir "tools"
            if (Test-Path $toolsDir) {
                $toolExes = Get-ChildItem $toolsDir -Filter "*.exe" -ErrorAction SilentlyContinue
                $toolBats = Get-ChildItem $toolsDir -Filter "*.bat" -ErrorAction SilentlyContinue
                $toolVbs = Get-ChildItem $toolsDir -Filter "*.vbs" -ErrorAction SilentlyContinue

                $startMenuDir = Join-Path ([Environment]::GetFolderPath("CommonPrograms")) "WPILib $year"
                if (-not (Test-Path $startMenuDir)) {
                    New-Item -ItemType Directory -Path $startMenuDir -Force | Out-Null
                }

                $toolCount = 0
                foreach ($tool in ($toolExes + $toolBats)) {
                    if ($tool.Name -match "(ToolsUpdater|processstarter)") { continue }
                    $toolShortcut = $shell.CreateShortcut((Join-Path $startMenuDir "$($tool.BaseName).lnk"))
                    $toolShortcut.TargetPath = $tool.FullName
                    $toolShortcut.WorkingDirectory = $toolsDir
                    $toolShortcut.Save()
                    $toolCount++
                }
                Write-Step "Created $toolCount tool shortcuts in Start Menu" "OK"
            }
        }

        # ── AdvantageScope shortcut ──
        $advantageScope = Join-Path $yearDir "advantagescope\AdvantageScope (WPILib).exe"
        if (-not (Test-Path $advantageScope)) {
            $advantageScope = Get-ChildItem (Join-Path $yearDir "advantagescope") -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($advantageScope) { $advantageScope = $advantageScope.FullName }
        }
        if ($advantageScope -and (Test-Path $advantageScope)) {
            $asShortcut = $shell.CreateShortcut((Join-Path $desktopPath "AdvantageScope $year.lnk"))
            $asShortcut.TargetPath = $advantageScope
            $asShortcut.Save()
            Write-Step "AdvantageScope desktop shortcut created" "OK"
        }

        # ── Elastic Dashboard shortcut ──
        $elastic = Get-ChildItem (Join-Path $yearDir "elastic") -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($elastic) {
            $elShortcut = $shell.CreateShortcut((Join-Path $desktopPath "Elastic Dashboard $year.lnk"))
            $elShortcut.TargetPath = $elastic.FullName
            $elShortcut.Save()
            Write-Step "Elastic Dashboard desktop shortcut created" "OK"
        }

        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
    }
    catch {
        Write-Step "Shortcut creation failed: $_" "WARN"
        Write-Step "You can still launch tools from: $yearDir\tools\" "INFO"
    }

    # ── Add frccode to system PATH ──
    Write-Step "Adding frccode to system PATH..." "ACTION"
    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    if ($machinePath -notlike "*$frcCodeDir*") {
        [Environment]::SetEnvironmentVariable("PATH", "$machinePath;$frcCodeDir", "Machine")
        $env:PATH = "$env:PATH;$frcCodeDir"
        Write-Step "Added to system PATH: $frcCodeDir" "OK"
    }
    else {
        Write-Step "Already in system PATH: $frcCodeDir" "SKIP"
    }

    # Also set JAVA_HOME at the machine level for builds
    Write-Step "Setting system JAVA_HOME..." "ACTION"
    $jdkPath = Join-Path $yearDir "jdk"
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $jdkPath, "Machine")
    $env:JAVA_HOME = $jdkPath
    Write-Step "JAVA_HOME = $jdkPath (system-wide)" "OK"
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 8: COPILOT CLI (STRETCH GOAL)
# ─────────────────────────────────────────────────────────────────────────────

function Install-CopilotCLI {
    Write-Banner "Phase 8: Copilot CLI — WPILib Integration (Stretch Goal)"

    if ($SkipCopilotCLI) {
        Write-Step "Skipping Copilot CLI setup (-SkipCopilotCLI)" "SKIP"
        return
    }

    $yearDir    = $script:Config.YearDir
    $year       = $script:Config.Year
    $frcCodeDir = Join-Path $yearDir "frccode"
    $ghAuthenticated = $false

    # ── Step 1: Ensure gh CLI is installed ──
    # Refresh PATH to pick up any recently installed programs
    $env:PATH = [Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("PATH", "User")

    if (-not (Test-CommandExists "gh")) {
        Write-Step "GitHub CLI (gh) not found — attempting install via winget" "ACTION"
        try {
            winget install --id GitHub.cli --silent --accept-package-agreements --accept-source-agreements 2>&1 |
                ForEach-Object { Write-Step "  $_" "INFO" }
            # Reload PATH after install
            $env:PATH = [Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                        [Environment]::GetEnvironmentVariable("PATH", "User")
        }
        catch {
            Write-Step "winget install failed: $_" "WARN"
        }
    }

    if (Test-CommandExists "gh") {
        $ghVer = gh --version 2>&1 | Select-Object -First 1
        Write-Step "GitHub CLI: $ghVer" "OK"
    }
    else {
        Write-Step "GitHub CLI not available — install from https://cli.github.com/" "WARN"
        Write-Step "Then run: gh auth login && gh extension install github/gh-copilot" "INFO"
        # Continue to create local WPILib assets even without gh installed
    }

    # ── Step 2: Check authentication ──
    if (Test-CommandExists "gh") {
        $authStatus = gh auth status 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Step "GitHub CLI authenticated" "OK"
            $ghAuthenticated = $true
        }
        else {
            Write-Step "GitHub CLI is installed but NOT authenticated" "WARN"
            Write-Step "To authenticate (run in any terminal, admin not required):" "INFO"
            Write-Step "  gh auth login" "INFO"
            Write-Step "Then install Copilot CLI extension:" "INFO"
            Write-Step "  gh extension install github/gh-copilot" "INFO"
        }
    }

    # ── Step 3: Install gh-copilot extension ──
    if ($ghAuthenticated) {
        $extensions = gh extension list 2>&1
        if ($extensions -match "copilot") {
            Write-Step "gh-copilot extension already installed" "SKIP"
        }
        else {
            Write-Step "Installing gh-copilot extension..." "ACTION"
            try {
                gh extension install github/gh-copilot 2>&1 | ForEach-Object { Write-Step "  $_" "INFO" }
                Write-Step "gh-copilot extension installed" "OK"
            }
            catch {
                Write-Step "Failed to install gh-copilot: $_" "WARN"
                Write-Step "Manually run: gh extension install github/gh-copilot" "INFO"
            }
        }

        $copilotVersion = gh copilot --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Step "gh copilot version: $copilotVersion" "OK"
        }
    }

    # ── Step 4: Create WPILib integration files ──
    # These are created regardless of gh auth status so they're ready when auth is set up

    Write-Step "Creating WPILib Copilot integration scripts in $frcCodeDir" "ACTION"
    if (-not (Test-Path $frcCodeDir)) { New-Item -ItemType Directory -Path $frcCodeDir -Force | Out-Null }

    # frc-ai.cmd  — wraps 'gh copilot suggest -t powershell' with WPILib env loaded
    $frcAiCmd = Join-Path $frcCodeDir "frc-ai.cmd"
    @"
@echo off
REM WPILib FRC AI Assistant
REM Wraps 'gh copilot suggest' with the WPILib build environment pre-loaded.
REM Usage: frc-ai [optional question]
REM   frc-ai                                  -- interactive
REM   frc-ai "how do I deploy my robot code"  -- direct question
call "%~dp0frcvars${year}.bat"
if "%~1"=="" (
    echo.
    echo  WPILib FRC AI Assistant  ^(gh copilot suggest^)
    echo  ─────────────────────────────────────────────────────
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

    # frc-ai.ps1  — PowerShell version of frc-ai
    $frcAiPs1 = Join-Path $frcCodeDir "frc-ai.ps1"
    @"
# WPILib FRC AI Assistant (PowerShell)
# Wraps 'gh copilot suggest' with the WPILib build environment pre-loaded.
# Usage:  .\frc-ai.ps1 [optional question]
param([Parameter(ValueFromRemainingArguments)][string[]]`$Question)

`$wpilibHome = Join-Path `$PSScriptRoot '..'
`$env:JAVA_HOME = Join-Path `$wpilibHome 'jdk'
`$env:PATH = "`$env:JAVA_HOME\bin;`$env:PATH"

`$q = `$Question -join ' '
if (-not `$q) {
    Write-Host ''
    Write-Host '  WPILib FRC AI Assistant  (gh copilot suggest)' -ForegroundColor Magenta
    Write-Host '  ─────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host '  Useful starting questions:' -ForegroundColor Cyan
    '  how do I build my robot project',
    '  how do I deploy to the roboRIO',
    '  how do I add a WPILib vendor library',
    '  how do I run desktop simulation',
    '  show me a Command-Based subsystem template',
    '  how do I run just my unit tests' | ForEach-Object { Write-Host "    frc-ai '`$_'" -ForegroundColor White }
    Write-Host ''
    gh copilot suggest -t powershell
} else {
    gh copilot suggest -t powershell `$q
}
"@ | Set-Content $frcAiPs1 -Encoding UTF8
    Write-Step "Created: $frcAiPs1" "OK"

    # frc-explain.cmd  — wraps 'gh copilot explain' with WPILib env loaded
    $frcExplainCmd = Join-Path $frcCodeDir "frc-explain.cmd"
    @"
@echo off
REM WPILib FRC Explain
REM Explains a shell command or WPILib concept using gh copilot explain.
REM Usage: frc-explain "command or concept to explain"
REM   frc-explain "./gradlew deploy -Pteam=1234"
REM   frc-explain "what does RobotContainer.java do"
call "%~dp0frcvars${year}.bat"
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

    # frc-explain.ps1  — PowerShell version of frc-explain
    $frcExplainPs1 = Join-Path $frcCodeDir "frc-explain.ps1"
    @"
# WPILib FRC Explain (PowerShell)
# Explains a shell command or WPILib concept using gh copilot explain.
# Usage:  .\frc-explain.ps1 'command or concept'
param([Parameter(ValueFromRemainingArguments)][string[]]`$Input)

`$wpilibHome = Join-Path `$PSScriptRoot '..'
`$env:JAVA_HOME = Join-Path `$wpilibHome 'jdk'
`$env:PATH = "`$env:JAVA_HOME\bin;`$env:PATH"

`$q = `$Input -join ' '
if (-not `$q) {
    Write-Host 'Usage: frc-explain.ps1 <command or concept>' -ForegroundColor Yellow
    Write-Host "  frc-explain.ps1 './gradlew deploy -Pteam=1234'" -ForegroundColor White
    Write-Host "  frc-explain.ps1 'what does WPILib Command-Based framework mean'" -ForegroundColor White
} else {
    gh copilot explain `$q
}
"@ | Set-Content $frcExplainPs1 -Encoding UTF8
    Write-Step "Created: $frcExplainPs1" "OK"

    # ── Step 5: Write the copilot-instructions.md template ──
    # Teams copy this file to <robot-project>/.github/copilot-instructions.md
    # GitHub Copilot (VS Code, CLI, web) reads it as permanent project context.
    $instructionsPath = Join-Path $yearDir "wpilib-copilot-instructions.md"
    @"
# WPILib FRC Robot Code — GitHub Copilot Instructions

This repository contains FRC (FIRST Robotics Competition) robot code using WPILib $year.

## Project Overview
- **Build system**: Gradle with the GradleRIO plugin
- **Target hardware**: NI roboRIO running Java (or C++)
- **WPILib version**: $($script:Config.Version)
- **Framework**: Command-Based (subsystems + commands in `src/main/java/frc/robot/`)

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
- Subsystems extend `SubsystemBase` and live in `subsystems/`
- Command factory methods are preferred over extending `Command` directly
  (e.g., `Commands.runOnce(...)` or `subsystem.myCommand()`)
- `RobotContainer.java` wires everything: instantiates subsystems, binds joystick
  buttons via `trigger.onTrue(command)`
- Hardware port numbers and PID constants belong in `Constants.java`
- Always guard hardware-only code with `RobotBase.isReal()` for simulation compat

## Key WPILib APIs to Know
- Motors: `TalonFX`, `SparkMax` (via vendor libs), `PWMMotorController`
- Sensors: `DigitalInput`, `AnalogInput`, `DutyCycleEncoder`, `ADIS16470_IMU`
- Pneumatics: `Solenoid` / `DoubleSolenoid` via `PneumaticHub` (CTRE)
- NetworkTables: `NetworkTableInstance.getDefault()` for telemetry
- Path following: `AutoBuilder` (PathPlanner) or `RamseteCommand` (built-in)
- Alerts: `Alert` class for driver station messages (WPILib 2025+)

## Simulation Notes
- Desktop simulation requires x64 JDK (WPILib JNI libs are x64-only on Windows)
  JAVA_HOME should point to `C:/Users/Public/wpilib/$year/jdk`
- Simulation uses `REVPhysicsSim`, `DCMotorSim`, etc. from WPILib
- Use `RobotBase.isSimulation()` to swap in simulated hardware

## Copilot AI Shortcuts (from terminal)
``````bash
frc-ai "how do I add a subsystem"          # gh copilot suggest with WPILib context
frc-ai "deploy command for team 1234"      # direct question
frc-explain "./gradlew deploy -Pteam=1234" # explain a command
``````
"@ | Set-Content $instructionsPath -Encoding UTF8
    Write-Step "Created template: $instructionsPath" "OK"
    Write-Step "  Copy this to <your-robot-project>/.github/copilot-instructions.md" "INFO"
    Write-Step "  It primes GitHub Copilot (VS Code + CLI + web) with WPILib context" "INFO"

    # ── Summary ──
    Write-Host ""
    Write-SectionHeader "Copilot CLI — WPILib Integration Summary"
    Write-Host "  Commands added to frccode/ (already on system PATH):" -ForegroundColor Cyan
    Write-Host "    frc-ai [question]     -- AI command suggestions (gh copilot suggest)" -ForegroundColor White
    Write-Host "    frc-explain [text]    -- AI explanations (gh copilot explain)" -ForegroundColor White
    Write-Host "" 
    Write-Host "  Project template (copy into any robot project):" -ForegroundColor Cyan
    Write-Host "    $instructionsPath" -ForegroundColor White
    Write-Host "    -> .github/copilot-instructions.md" -ForegroundColor DarkGray
    Write-Host ""
    if (-not $ghAuthenticated) {
        Write-Host "  PENDING: Complete GitHub CLI authentication:" -ForegroundColor Yellow
        Write-Host "    gh auth login" -ForegroundColor Yellow
        Write-Host "    gh extension install github/gh-copilot" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 9: VERIFICATION (ARM64-ENHANCED)
# ─────────────────────────────────────────────────────────────────────────────

function Test-Installation {
    Write-Banner "Phase 9: Installation Verification (ARM64)"

    $yearDir = $script:Config.YearDir
    $results = @()
    $script:passCount = 0
    $script:failCount = 0

    function Add-TestResult {
        param([string]$Test, [bool]$Passed, [string]$Detail = "")
        $status = if ($Passed) { "PASS" } else { "FAIL" }
        $color = if ($Passed) { "OK" } else { "ERROR" }
        $msg = "${status}: ${Test}"
        if ($Detail) { $msg += " — $Detail" }
        Write-Step $msg $color
        if ($Passed) { $script:passCount++ } else { $script:failCount++ }
    }

    # ── ARM64 Detection ──
    Add-TestResult "ARM64 system detected" (Test-IsArm64System) $env:PROCESSOR_ARCHITECTURE

    # ── JDK 17 (builds) ──
    $javaExe = Join-Path $yearDir "jdk\bin\java.exe"
    $javaPresent = Test-Path $javaExe
    $javaDetail = ""
    $jdkIsArm64 = $false
    if ($javaPresent) {
        $javaDetail = (& $javaExe -version 2>&1 | Select-Object -First 1) -replace '"', ''

        # Check if JDK is ARM64 native
        if ($UseArm64Jdk) {
            try {
                $bytes = [System.IO.File]::ReadAllBytes($javaExe)
                $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
                $machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
                $jdkIsArm64 = ($machine -eq 0xAA64)
                if ($jdkIsArm64) {
                    $javaDetail += " [ARM64-native]"
                }
                else {
                    $javaDetail += " [x64-emulated]"
                }
            }
            catch {}
        }
    }
    Add-TestResult "JDK 17 installed (robot builds)" $javaPresent $javaDetail

    # ── JDK 21 (language server) ──
    $java21Exe = Join-Path $yearDir "jdk21ls\bin\java.exe"
    $java21Present = Test-Path $java21Exe
    $java21Detail = ""
    if ($java21Present) {
        $java21Detail = (& $java21Exe -version 2>&1 | Select-Object -First 1) -replace '"', ''
    }
    Add-TestResult "JDK 21 installed (VS Code language server)" $java21Present $java21Detail

    if ($UseArm64Jdk) {
        Add-TestResult "JDK is ARM64-native" $jdkIsArm64 $(if ($jdkIsArm64) { "Microsoft OpenJDK ARM64" } else { "Expected ARM64 but got x64" })
        Add-TestResult "JNI simulation compatible" $false "ARM64 JVM cannot load x64 native DLLs — simulation BROKEN"
    }
    else {
        Add-TestResult "JNI simulation compatible" $true "x64 JDK loads x64 DLLs natively under Prism"
    }

    # ── roboRIO Toolchain ──
    $toolchainPresent = Test-Path (Join-Path $yearDir "roborio")
    $gccPath = Get-ChildItem (Join-Path $yearDir "roborio") -Filter "arm-frc*-g++*" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    Add-TestResult "roboRIO C++ toolchain (x64/emulated)" $toolchainPresent $(if ($gccPath) { "$($gccPath.Name) [runs under Prism]" })

    # ── Maven Repository ──
    $mavenPresent = Test-Path (Join-Path $yearDir "maven")
    $mavenSize = 0
    if ($mavenPresent) {
        $mavenSize = [math]::Round(((Get-ChildItem (Join-Path $yearDir "maven") -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1GB), 2)
    }
    Add-TestResult "Offline Maven repository" $mavenPresent "${mavenSize} GB"

    # ── VS Code Extensions ──
    $extensions = @(code --list-extensions 2>$null)
    $wpilibExt = @($extensions -match "wpilibsuite")
    Add-TestResult "WPILib VS Code extension" ($wpilibExt.Count -gt 0) ($wpilibExt -join ", ")

    $cppExt = @($extensions -match "ms-vscode.cpptools")
    Add-TestResult "C/C++ extension (ARM64 from Marketplace)" ($cppExt.Count -gt 0)

    $javaExt = @($extensions -match "redhat.java")
    Add-TestResult "Java Language extension (ARM64 from Marketplace)" ($javaExt.Count -gt 0)

    $javaDebugExt = @($extensions -match "vscjava.vscode-java-debug")
    Add-TestResult "Java Debug extension" ($javaDebugExt.Count -gt 0)

    $javaDepsExt = @($extensions -match "vscjava.vscode-java-dependency")
    Add-TestResult "Java Dependency extension" ($javaDepsExt.Count -gt 0)

    # ── Gradle Cache ──
    $gradleCache = @(Get-ChildItem (Join-Path $env:USERPROFILE ".gradle\wrapper\dists") -Filter "gradle-*-bin" -Directory -ErrorAction SilentlyContinue)
    Add-TestResult "Gradle wrapper cached" ($gradleCache.Count -gt 0) $(if ($gradleCache.Count -gt 0) { $gradleCache[0].Name })

    # ── Desktop Tools ──
    $toolsDir = Join-Path $yearDir "tools"
    $toolsPresent = Test-Path $toolsDir
    $toolCount = 0
    if ($toolsPresent) {
        $toolCount = @(Get-ChildItem $toolsDir -Filter "*.exe" -ErrorAction SilentlyContinue).Count +
                     @(Get-ChildItem $toolsDir -Filter "*.bat" -ErrorAction SilentlyContinue).Count
    }
    Add-TestResult "Desktop tools" $toolsPresent "$toolCount executables/scripts (x64/emulated + Java/native)"

    # ── AdvantageScope ──
    $asPresent = Test-Path (Join-Path $yearDir "advantagescope")
    Add-TestResult "AdvantageScope" $asPresent

    # ── Elastic Dashboard ──
    $elasticPresent = Test-Path (Join-Path $yearDir "elastic")
    Add-TestResult "Elastic Dashboard (x64/emulated)" $elasticPresent

    # ── Vendor Dependencies ──
    $vendordeps = Join-Path $yearDir "vendordeps"
    $vdPresent = Test-Path $vendordeps
    $vdCount = 0
    if ($vdPresent) { $vdCount = @(Get-ChildItem $vendordeps -Filter "*.json").Count }
    Add-TestResult "Vendor dependencies" $vdPresent "$vdCount JSON files"

    # ── Environment ──
    $javaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
    Add-TestResult "JAVA_HOME (system)" ($null -ne $javaHome -and (Test-Path $javaHome)) $javaHome

    $frcCodeInPath = ([Environment]::GetEnvironmentVariable("PATH", "Machine")) -like "*frccode*"
    Add-TestResult "frccode in PATH" $frcCodeInPath

    # ── VS Code Settings ──
    $settingsPath = Join-Path $env:APPDATA "Code\User\settings.json"
    $settingsOk = $false
    if (Test-Path $settingsPath) {
        $settingsContent = Get-Content $settingsPath -Raw
        $settingsOk = $settingsContent -like "*wpilib*" -or $settingsContent -like "*JavaSE-17*"
    }
    Add-TestResult "VS Code settings configured" $settingsOk

    # ── Copilot CLI ──
    if (-not $SkipCopilotCLI) {
        $ghCopilotWorks = $false
        if (Test-CommandExists "gh") {
            $ghCopilotCheck = gh copilot --version 2>&1
            $ghCopilotWorks = ($LASTEXITCODE -eq 0)
        }
        Add-TestResult "Copilot CLI" $ghCopilotWorks "(stretch goal)"
    }

    # ── Summary ──
    Write-Host ""
    Write-Host ("─" * 60) -ForegroundColor $(if ($script:failCount -eq 0) { "Green" } else { "Yellow" })
    $total = $script:passCount + $script:failCount
    Write-Host "  Results: $($script:passCount)/$total passed" -ForegroundColor $(if ($script:failCount -eq 0) { "Green" } else { "Yellow" })
    if ($script:failCount -gt 0) {
        Write-Host "  $($script:failCount) test(s) failed — review output above" -ForegroundColor Yellow
    }
    Write-Host ("─" * 60) -ForegroundColor $(if ($script:failCount -eq 0) { "Green" } else { "Yellow" })

    # ── ARM64 Architecture Report ──
    Write-Host ""
    Write-SectionHeader "ARM64 Architecture Report"

    Write-Step "Components running NATIVELY on ARM64:" "ARM64"
    foreach ($comp in $script:Arm64Report.NativeComponents) {
        Write-Step "  ✓ $comp" "OK"
    }

    Write-Host ""
    Write-Step "Components running under Prism x64 EMULATION:" "ARM64"
    foreach ($comp in $script:Arm64Report.EmulatedComponents) {
        Write-Step "  ~ $comp" "WARN"
    }

    Write-Host ""
    Write-Step "Emulated components work correctly but may have ~20-50% performance overhead" "INFO"
    Write-Step "C++ builds (roboRIO cross-compile) will be slower; Java builds run at native speed" "INFO"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ─────────────────────────────────────────────────────────────────────────────

function Main {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Banner "WPILib FrankenCode Installer v1.2.0-arm64"
    Write-Step "WPILib Version: $($script:Config.Version)" "INFO"
    Write-Step "Season Year: $($script:Config.Year)" "INFO"
    Write-Step "Install Dir: $($script:Config.YearDir)" "INFO"
    Write-Step "Download Dir: $($script:Config.DownloadDir)" "INFO"
    Write-Step "Platform: Windows ARM64" "ARM64"
    Write-Step "JDK Strategy: $(if ($UseArm64Jdk) { 'ARM64-native Microsoft OpenJDK (NO simulation)' } else { 'x64 Temurin from ISO under Prism emulation (simulation compatible)' })" "ARM64"
    Write-Step "JDK 21 LS: Microsoft OpenJDK 21 ARM64 (VS Code language server, native)" "ARM64"
    Write-Step "Official ARM64 support: Expected in WPILib 2027 (allwpilib #3165)" "ARM64"
    Write-Host ""

    # Phase 0: Prerequisites
    Test-Prerequisites

    # Phase 1: Download ISO
    $isoPath = Get-WPILibISO

    # Phase 2: Mount & Extract (skips x64 JDK if replacing)
    Install-FromISO -IsoPath $isoPath

    # Phase 2B: Install ARM64-native JDK
    Install-Arm64Jdk

    # Phase 2C: Install ARM64 AdvantageScope
    Install-Arm64AdvantageScope

    # Phase 2D: JDK 21 for VS Code Java Language Server
    Install-Jdk21LanguageServer

    # Phase 3: Gradle Cache
    Install-GradleCache

    # Phase 4: Tools & Maven
    Install-ToolsAndMaven

    # Phase 5: VS Code Extensions (ARM64-aware)
    Install-VSCodeExtensions

    # Phase 6: VS Code Settings
    Set-VSCodeSettings

    # Phase 7: Environment & Shortcuts
    Install-EnvironmentHelpers

    # Phase 8: Copilot CLI
    Install-CopilotCLI

    # Phase 9: Verification
    Test-Installation

    $stopwatch.Stop()
    $elapsed = $stopwatch.Elapsed

    Write-Banner "Installation Complete! (ARM64)"
    Write-Step "Total time: $($elapsed.ToString('hh\:mm\:ss'))" "INFO"
    Write-Step "" "INFO"
    Write-Step "Next steps:" "INFO"
    Write-Step "  1. Restart VS Code to activate extensions" "INFO"
    Write-Step "  2. Press Ctrl+Shift+P → type 'WPILib' → verify commands appear" "INFO"
    Write-Step "  3. Create a new project: 'WPILib: Create a new project'" "INFO"
    Write-Step "  4. Build: 'WPILib: Build Robot Code'" "INFO"
    Write-Step "" "INFO"
    Write-Step "ARM64 Notes:" "ARM64"
    Write-Step "  • Java builds (Gradle) run at native ARM64 speed" "INFO"
    Write-Step "  • C++ cross-compilation uses x64 GCC under Prism emulation (~30-50% slower)" "INFO"
    Write-Step "  • Desktop tools with native x64 components run under emulation" "INFO"
    Write-Step "" "INFO"
    Write-Step "FrankenCode launcher: $($script:Config.YearDir)\frccode\FrankenCode$($script:Config.Year).cmd" "INFO"
    Write-Step "Desktop shortcut: 'WPILib FrankenCode $($script:Config.Year) (ARM64)'" "INFO"
}

# Run!
Main
