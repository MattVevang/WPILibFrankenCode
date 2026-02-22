# WPILib FrankenCode

**Unlock WPILib FRC development tools in modern VS Code — no version-locked IDE required.**

WPILib ships a pinned, older version of VS Code that prevents using the latest Copilot extension, modern themes, and other marketplace tools. This project automates the installation of all WPILib 2026 components into your **existing, up-to-date VS Code** — creating a "FrankenCode" hybrid that gives you the best of both worlds.

## What It Does

A single PowerShell script (`Install-WPILibFrankenCode.ps1`) that:

1. **Downloads** the official WPILib 2026.2.1 ISO (2.4 GB)
2. **Extracts** all development artifacts — but **skips the bundled VS Code**
3. **Installs** the WPILib extension + companion extensions into your modern VS Code
4. **Configures** JDK 17, Gradle caches, Maven offline repo, and VS Code settings
5. **Sets up** desktop tools (Shuffleboard, Glass, AdvantageScope, Elastic, SysId, etc.)
6. **Creates** Start Menu shortcuts and desktop launchers
7. **Verifies** everything works with a 17-point test suite

### Components Installed

| Component | Version | Location |
|---|---|---|
| JDK (Adoptium Temurin) | 17.0.16+8 | `C:\Users\Public\wpilib\2026\jdk\` |
| roboRIO C++ Toolchain | GCC 12.1.0 | `C:\Users\Public\wpilib\2026\roborio\` |
| Offline Maven Repository | 2026.2.1 | `C:\Users\Public\wpilib\2026\maven\` |
| Gradle Wrapper | 8.11 | `~\.gradle\wrapper\dists\` |
| WPILib VS Code Extension | 2026.2.1 | VS Code extensions dir |
| C/C++ Extension | 1.28.3 | VS Code extensions dir |
| Java Language Extension | 1.38.0 | VS Code extensions dir |
| Java Debug Extension | 0.58.2 | VS Code extensions dir |
| Java Dependency Extension | 0.24.1 | VS Code extensions dir |
| AdvantageScope | v26.0.0 | `C:\Users\Public\wpilib\2026\advantagescope\` |
| Elastic Dashboard | v2026.1.1 | `C:\Users\Public\wpilib\2026\elastic\` |
| Desktop Tools | 2026.2.1 | `C:\Users\Public\wpilib\2026\tools\` |

## Quick Start

### Prerequisites

- **Windows 11** with Administrator access
- **VS Code** (latest, installed via winget or directly)
- **Git** (recommended)
- **~5 GB** free disk space
- **Internet connection** (for initial ISO download)

### Run

```powershell
# Open PowerShell as Administrator, then:
cd C:\src\WPILibFrankenCode
.\Install-WPILibFrankenCode.ps1
```

### Options

```powershell
# Skip re-downloading if ISO already cached
.\Install-WPILibFrankenCode.ps1 -SkipDownload

# Overwrite existing installation without prompting
.\Install-WPILibFrankenCode.ps1 -Force

# Skip desktop tools (Shuffleboard, Glass, etc.)
.\Install-WPILibFrankenCode.ps1 -SkipDesktopTools

# Skip Copilot CLI setup
.\Install-WPILibFrankenCode.ps1 -SkipCopilotCLI

# Combine options
.\Install-WPILibFrankenCode.ps1 -Force -SkipDownload
```

## How It Works

The key insight: **the WPILib VS Code extension only requires VS Code `^1.57.0`** — any modern VS Code satisfies this. The version-locked bundled VS Code is a distribution choice, not a technical requirement.

The script:
1. Downloads and mounts the official WPILib ISO
2. Extracts all artifacts **except the bundled VS Code** into `C:\Users\Public\wpilib\2026\`
3. Reads the installer's JSON config files to discover exact versions and hashes
4. Installs VSIX extensions into the system VS Code via `code --install-extension`
5. Merges WPILib settings into VS Code's `settings.json` (non-destructively)
6. Sets up Gradle wrapper cache with the correct hash directory
7. Runs `ToolsUpdater.jar` and `MavenMetaDataFixer.jar` for desktop tools and offline builds
8. Sets `JAVA_HOME` system-wide and adds `frccode` to system `PATH`

## After Installation

1. **Restart VS Code** to activate the new extensions
2. Press `Ctrl+Shift+P` → type **"WPILib"** → verify commands appear
3. Use **"WPILib: Create a new project"** to scaffold a robot project
4. Use **"WPILib: Build Robot Code"** to build with Gradle

## Copilot CLI (Stretch Goal)

If GitHub CLI is installed and authenticated, the script also sets up `gh copilot` for terminal-based AI assistance:

```powershell
gh copilot suggest "how to create a WPILib command-based robot"
gh copilot explain "what does GradleRIO do"
```

## Windows ARM64 Support

A dedicated ARM64 variant is available: `Install-WPILibFrankenCode-ARM64.ps1`

This script uses the same x64 WPILib ISO (there is no official ARM64 ISO) but adapts architecture-sensitive components for ARM64 Windows. **By default it uses the x64 JDK under Prism emulation** to ensure full compatibility with simulation and unit tests.

> **Official WPILib ARM64 support is expected in 2027** ([allwpilib #3165](https://github.com/wpilibsuite/allwpilib/issues/3165)). This installer serves the gap between now and then.

### Known Limitations on ARM64

| Issue | Severity | Detail |
|---|---|---|
| **JNI simulation (with `-UseArm64Jdk`)** | **BLOCKER** | ARM64 JVM cannot load x64 native DLLs. `simulateJava`, `simulateNative`, and JNI-based unit tests fail with `UnsatisfiedLinkError`. **Default config (x64 JDK) avoids this.** |
| **GradleRIO resolution (with `-UseArm64Jdk`)** | HIGH | ARM64 JDK reports `os.arch=aarch64`, causing Gradle to resolve `windowsarm64` native artifacts. Vendor libraries (CTRE, REV, PhotonVision) don't publish these. |
| **No official support** | MEDIUM | WPILib requirements state "Arm is not supported." Untested by the WPILib team on Windows ARM64 hardware until recently. |
| **NI kernel drivers** | MEDIUM | FRC Driver Station and roboRIO Imaging Tool run under x64 emulation, but their USB kernel drivers may require ARM64-native builds. Network-based deploy is unaffected. |
| **C++ desktop builds** | LOW | Gradle's native C++ plugin doesn't support ARM64 Windows hosts. C++ builds use the x64 GCC cross-compiler under emulation (~30-50% slower). |
| **Elastic Dashboard** | LOW | No ARM64 build exists (Flutter). Runs under x64 emulation. |

**Why macOS ARM64 is supported but Windows ARM64 is not:** Apple's toolchain enables trivial cross-compilation (`-target arm64-apple-macos11`), JavaFX has mature macOS ARM64 builds (via Azul/GluonHQ), and Apple Silicon rapidly became the majority Mac platform. None of these advantages existed for Windows ARM64 — JavaFX Windows ARM64 builds are scarce (the primary blocker), and the WPILib team had no test hardware until 2025. The 2027 release removes all JavaFX tools, eliminating the main blocker.

### What Works Perfectly on ARM64

- VS Code with all WPILib commands (ARM64-native)
- Java code compilation and Gradle builds (deploy to roboRIO)
- cpptools IntelliSense for C++ (ARM64 builds since 2021)
- Java Language Server (runs on JDK, any architecture)
- AdvantageScope (ARM64-native Electron build)
- Project creation, templates, vendor dependency management
- Network-based robot communication (deploy, NetworkTables, SSH)
- Pure-Java vendor libraries (PathPlannerLib, AdvantageKit, Limelight)

### ARM64 Component Matrix (Default Config)

| Component | Strategy | Speed | Simulation? |
|---|---|---|---|
| **JDK 17** | x64 Temurin under Prism (default) | Emulated | **Yes** |
| **JDK 17** | ARM64 Microsoft OpenJDK (`-UseArm64Jdk`) | **Native** | **No** |
| **Gradle** | Pure Java — runs on whichever JDK | Matches JDK | N/A |
| **cpptools / redhat.java** | Marketplace (auto-selects ARM64) | **Native** | N/A |
| **WPILib + JS extensions** | VSIX from ISO (architecture-independent) | **Native** | N/A |
| **AdvantageScope** | ARM64 build from GitHub releases | **Native** | N/A |
| **roboRIO toolchain** | x64 GCC under Prism emulation | ~30-50% slower | N/A |
| **Native tools** (Glass, SysId) | x64 under Prism emulation | ~20-30% slower | N/A |
| **Elastic Dashboard** | x64 Flutter under Prism emulation | ~20-30% slower | N/A |

### ARM64 Quick Start

```powershell
# Open PowerShell as Administrator on your ARM64 device, then:
cd C:\src\WPILibFrankenCode
.\Install-WPILibFrankenCode-ARM64.ps1
```

### ARM64 Options

```powershell
# Default: x64 JDK under emulation (full compatibility, simulation works)
.\Install-WPILibFrankenCode-ARM64.ps1

# Native ARM64 JDK (faster builds, but simulation and JNI tests BROKEN)
.\Install-WPILibFrankenCode-ARM64.ps1 -UseArm64Jdk

# Skip ARM64 AdvantageScope download (use x64 from ISO)
.\Install-WPILibFrankenCode-ARM64.ps1 -SkipAdvantageScopeArm64

# All standard options (-Force, -SkipDownload, etc.) also work
.\Install-WPILibFrankenCode-ARM64.ps1 -Force -SkipDownload
```

### Key Technical Details

- **Windows 11 Prism emulator** handles all x64 components transparently
- The script detects whether VS Code itself is ARM64-native (via PE header) and adjusts extension strategy
- The `-UseArm64Jdk` flag is opt-in because of the JNI blocker — read `Get-Help .\Install-WPILibFrankenCode-ARM64.ps1 -Full` for the complete known-limitations document
- The verification phase includes an ARM64 Architecture Report showing which components are native vs emulated

## Idempotency

The scripts are safe to re-run. They check for existing installations, validate component presence, and only overwrite when using `-Force`. The ISO download is skipped automatically if the file already exists at the expected size.

## License

MIT
