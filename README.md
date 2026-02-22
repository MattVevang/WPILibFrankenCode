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

This script uses the same x64 WPILib ISO (there is no official ARM64 ISO) but intelligently replaces architecture-sensitive components:

### ARM64 Component Matrix

| Component | ARM64 Strategy | Performance |
|---|---|---|
| **JDK 17** | Microsoft OpenJDK 17 ARM64 (downloaded separately) | **Native** |
| **Gradle** | Pure Java — runs on ARM64 JDK | **Native** |
| **Maven offline repo** | Architecture-independent JAR files | **Native** |
| **WPILib extension** | Pure JS — architecture-independent | **Native** |
| **Java debug/deps extensions** | Pure JS — architecture-independent | **Native** |
| **cpptools extension** | Downloaded from Marketplace (auto-selects ARM64) | **Native** |
| **redhat.java extension** | Downloaded from Marketplace (auto-selects ARM64) | **Native** |
| **Java tools** (Shuffleboard, PathWeaver, etc.) | Runs on ARM64 JDK | **Native** |
| **AdvantageScope** | ARM64 build downloaded from GitHub releases | **Native** |
| **roboRIO toolchain** (GCC cross-compiler) | x64 binaries under Prism emulation | ~30-50% slower |
| **Native tools** (Glass, SysId, DataLogTool) | x64 binaries under Prism emulation | ~20-30% slower |
| **Elastic Dashboard** | x64 Flutter app under Prism emulation | ~20-30% slower |

### ARM64 Quick Start

```powershell
# Open PowerShell as Administrator on your ARM64 device, then:
cd C:\src\WPILibFrankenCode
.\Install-WPILibFrankenCode-ARM64.ps1
```

### ARM64 Options

```powershell
# Use x64 JDK from ISO under emulation (skip downloading ARM64 JDK)
.\Install-WPILibFrankenCode-ARM64.ps1 -SkipJdkReplace

# Skip ARM64 AdvantageScope download (use x64 from ISO)
.\Install-WPILibFrankenCode-ARM64.ps1 -SkipAdvantageScopeArm64

# All standard options (-Force, -SkipDownload, etc.) also work
.\Install-WPILibFrankenCode-ARM64.ps1 -Force -SkipDownload
```

### Key Technical Details

- **Windows 11 Prism emulator** handles all x64 components transparently
- The script detects whether VS Code itself is ARM64-native and adjusts extension strategy accordingly
- **Java builds run at full native speed** — only C++ cross-compilation is affected by emulation
- The verification phase includes an ARM64 Architecture Report showing which components are native vs emulated

## Idempotency

The scripts are safe to re-run. They check for existing installations, validate component presence, and only overwrite when using `-Force`. The ISO download is skipped automatically if the file already exists at the expected size.

## License

MIT
