<#
.SYNOPSIS
    WPILib FrankenCode Installer — Installs WPILib 2026 components into modern VS Code.

.DESCRIPTION
    Downloads the official WPILib 2026.2.1 ISO, extracts all development artifacts
    (JDK 17, roboRIO toolchain, Maven offline repo, desktop tools, VSIX extensions)
    into C:\Users\Public\wpilib\2026\ — but SKIPS the bundled outdated VS Code.

    Then installs the WPILib extension + companion extensions into the user's
    existing modern VS Code, configures settings, sets up Gradle caches, and
    verifies everything works.

    Key insight: The WPILib VS Code extension requires engine ^1.57.0, so any
    modern VS Code satisfies this constraint.

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

.PARAMETER Force
    Overwrite existing installation without prompting.

.EXAMPLE
    .\Install-WPILibFrankenCode.ps1
    # Runs with all defaults — full installation

.EXAMPLE
    .\Install-WPILibFrankenCode.ps1 -SkipDesktopTools -SkipCopilotCLI
    # Minimal install — extensions and toolchain only

.NOTES
    Requires: Administrator privileges, VS Code installed, internet connection.
    Author:   WPILibFrankenCode Project
    Version:  1.1.0
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
    # JDK 21 for VS Code Java Language Server (required by redhat.java >= v1.30)
    # Separate from the WPILib build JDK 17 — the LS is pure Java, no JNI
    Jdk21LsUrl       = "https://aka.ms/download-jdk/microsoft-jdk-21-windows-x64.zip"
    Jdk21LsZipName   = "microsoft-jdk-21-windows-x64.zip"
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
# PHASE 0: PREREQUISITES
# ─────────────────────────────────────────────────────────────────────────────

function Test-Prerequisites {
    Write-Banner "Phase 0: Prerequisite Checks"

    $failed = $false

    # Check VS Code
    if (Test-CommandExists "code") {
        $codeVersion = (code --version | Select-Object -First 1).Trim()
        Write-Step "VS Code found: v$codeVersion" "OK"
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

    # Check disk space (need ~5GB for download + extraction)
    $drive = (Split-Path $script:Config.YearDir -Qualifier)
    $freeGB = [math]::Round((Get-PSDrive ($drive -replace ":","")).Free / 1GB, 1)
    if ($freeGB -ge 5) {
        Write-Step "Disk space: ${freeGB}GB free on $drive (need ~5GB)" "OK"
    }
    else {
        Write-Step "Insufficient disk space: ${freeGB}GB free, need ~5GB on $drive" "ERROR"
        $failed = $true
    }

    # Check network connectivity
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
        -Description "WPILib $($script:Config.Version) ISO"

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

        if (Test-Path $yearDir) {
            Write-Step "Cleaning existing directory: $yearDir" "WARN"
            # Don't nuke the whole dir — some items (like vscode/) shouldn't be created
            # We'll extract everything and clean up the bundled VS Code after
        }

        # Using Expand-Archive for the large file with -Force for overwrites
        if (-not (Test-Path $yearDir)) {
            New-Item -ItemType Directory -Path $yearDir -Force | Out-Null
        }

        # For a 2+ GB zip, use .NET directly for better performance
        Write-Step "Extracting (this may take 5-10 minutes)..." "ACTION"
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        $zip = [System.IO.Compression.ZipFile]::OpenRead($artifactsZip.FullName)
        $totalEntries = $zip.Entries.Count
        $extracted = 0
        $lastPercent = -1
        $skipPrefixes = @("vscode/")  # Skip the bundled VS Code

        try {
            foreach ($entry in $zip.Entries) {
                $extracted++
                $percent = [math]::Floor(($extracted / $totalEntries) * 100)

                # Progress reporting every 5%
                if ($percent -ne $lastPercent -and ($percent % 5 -eq 0)) {
                    Write-Progress -Activity "Extracting WPILib artifacts" `
                        -Status "$extracted of $totalEntries files ($percent%)" `
                        -PercentComplete $percent
                    $lastPercent = $percent
                }

                # Skip bundled VS Code directory — we use modern VS Code instead
                $skip = $false
                foreach ($prefix in $skipPrefixes) {
                    if ($entry.FullName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                        $skip = $true
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
        Write-Step "Extracted $extracted files to $yearDir" "OK"

        # Verify key directories exist
        $expectedDirs = @("jdk", "maven", "tools", "roborio", "vsCodeExtensions",
                          "vendordeps", "frccode", "installUtils", "icons")
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
# PHASE 2B: JDK 21 FOR VS CODE JAVA LANGUAGE SERVER
# ─────────────────────────────────────────────────────────────────────────────

function Install-Jdk21LanguageServer {
    Write-Banner "Phase 2B: JDK 21 Language Server Installation"

    # Why a second JDK?
    #   redhat.java (VS Code Java extension) >= v1.30 requires JDK 21+ to LAUNCH
    #   its embedded language server (Eclipse JDT-LS). This is separate from the
    #   JDK used to BUILD robot code — WPILib Gradle still targets JDK 17.
    #
    #   java.jdt.ls.java.home → JDK 21  (starts the IntelliSense daemon)
    #   java.configuration.runtimes → JDK 17 as default (compiles robot code)
    #   JAVA_HOME / terminal PATH    → JDK 17 (Gradle build path, unchanged)

    $yearDir     = $script:Config.YearDir
    $jdk21LsPath = Join-Path $yearDir "jdk21ls"
    $downloadDir = $script:Config.DownloadDir

    # Check if already installed and valid
    $jdk21Exe = Join-Path $jdk21LsPath "bin\java.exe"
    if (Test-Path $jdk21Exe) {
        $ver = (& $jdk21Exe -version 2>&1 | Select-Object -First 1) -replace '"', ''
        if ($ver -match '2[1-9]\.|[3-9]\d\.') {
            Write-Step "JDK 21 LS already installed: $ver" "SKIP"
            return
        }
    }

    Write-Step "Downloading Microsoft JDK 21 x64 for VS Code language server" "INFO"
    Write-Step "  JDK 17 (builds + simulation) is unchanged" "INFO"

    $jdk21ZipPath = Join-Path $downloadDir $script:Config.Jdk21LsZipName
    $needDownload = $true
    if (Test-Path $jdk21ZipPath) {
        $sz = (Get-Item $jdk21ZipPath).Length
        if ($sz -gt 100MB) {
            Write-Step "JDK 21 zip already cached ($('{0:N0}' -f ($sz/1MB)) MB) — reusing" "SKIP"
            $needDownload = $false
        } else {
            Remove-Item $jdk21ZipPath -Force
        }
    }
    if ($needDownload) {
        Invoke-DownloadWithProgress -Url $script:Config.Jdk21LsUrl -OutFile $jdk21ZipPath -Description "Microsoft JDK 21 x64 (language server)"
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
        # Compute the hash the same way Gradle does (the directory name is based on the URL hash)
        # Use a well-known hash for gradle-8.11-bin
        # The actual Gradle wrapper creates the hash from the distribution URL
        # We'll just create the directory and let Gradle sort it out on first run
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
        Write-Step "Running ToolsUpdater.jar..." "ACTION"
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
        Write-Step "Running MavenMetaDataFixer.jar..." "ACTION"
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
# PHASE 5: VS CODE EXTENSION INSTALLATION
# ─────────────────────────────────────────────────────────────────────────────

function Install-VSCodeExtensions {
    Write-Banner "Phase 5: VS Code Extension Installation"

    $yearDir = $script:Config.YearDir
    $vsixDir = Join-Path $yearDir "vsCodeExtensions"

    if (-not (Test-Path $vsixDir)) {
        Write-Step "VSIX directory not found: $vsixDir" "ERROR"
        return
    }

    # Get all VSIX files
    $vsixFiles = Get-ChildItem $vsixDir -Filter "*.vsix"
    Write-Step "Found $($vsixFiles.Count) VSIX files:" "INFO"
    foreach ($vsix in $vsixFiles) {
        Write-Step "  $($vsix.Name) ($('{0:N1}' -f ($vsix.Length / 1MB)) MB)" "INFO"
    }

    # Get currently installed extensions
    $installedExtensions = @(code --list-extensions 2>$null)
    Write-Step "Currently installed extensions: $($installedExtensions.Count)" "INFO"

    # Install order matters — install dependencies first
    $installOrder = @(
        "*cpptools*",
        "*java-1*",          # redhat.java (language server)
        "*java-debug*",
        "*java-dependency*",
        "*wpilib*"           # WPILib extension last (depends on others)
    )

    $installedCount = 0
    $failedCount = 0

    foreach ($pattern in $installOrder) {
        $matchingVsix = $vsixFiles | Where-Object { $_.Name -like $pattern } | Select-Object -First 1
        if (-not $matchingVsix) {
            # Try broader match
            $matchingVsix = $vsixFiles | Where-Object { $_.Name -like "*$($pattern.Trim('*'))*" } | Select-Object -First 1
        }
        if (-not $matchingVsix) { continue }

        Write-Step "Installing: $($matchingVsix.Name)..." "ACTION"
        try {
            $output = & code --install-extension $matchingVsix.FullName --force 2>&1
            $outputStr = ($output | Out-String)
            $output | ForEach-Object { Write-Step "  $_" "INFO" }

            if ($outputStr -match "restart VS Code") {
                Write-Step "Extension locked by running VS Code — already installed, will activate after restart" "WARN"
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
        $vsixFiles = $vsixFiles | Where-Object { $_.FullName -ne $matchingVsix.FullName }
    }

    # Install any remaining VSIX files not caught by the ordered patterns
    foreach ($vsix in $vsixFiles) {
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
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 6: VS CODE SETTINGS CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

function Set-VSCodeSettings {
    Write-Banner "Phase 6: VS Code Settings Configuration"

    $yearDir     = $script:Config.YearDir
    $jdkPath     = Join-Path $yearDir "jdk"      # JDK 17 — WPILib builds & Gradle
    $jdk21LsPath = Join-Path $yearDir "jdk21ls"  # JDK 21 — VS Code language server

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
# WPILib FrankenCode Environment Setup
`$WPILibHome = "$yearDir"
`$env:JAVA_HOME = "`$WPILibHome\jdk"
`$env:PATH = "`$WPILibHome\jdk\bin;`$env:PATH"
Write-Host "WPILib $year environment loaded (FrankenCode)" -ForegroundColor Green
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
echo WPILib $year environment loaded (FrankenCode)
"@ | Set-Content $frcVarsBat -Encoding ASCII
        Write-Step "Created: $frcVarsBat" "OK"
    }

    # ── Create a FrankenCode launcher script ──
    # This launches the SYSTEM VS Code (not bundled) with WPILib env set
    $frankenLauncher = Join-Path $frcCodeDir "FrankenCode${year}.cmd"
    @"
@echo off
REM WPILib FrankenCode Launcher — Opens modern VS Code with WPILib environment
call "%~dp0frcvars${year}.bat"
start "" code %*
"@ | Set-Content $frankenLauncher -Encoding ASCII
    Write-Step "Created FrankenCode launcher: $frankenLauncher" "OK"

    # ── Create Desktop Shortcut ──
    try {
        $shell = New-Object -ComObject WScript.Shell
        $desktopPath = [Environment]::GetFolderPath("Desktop")

        # WPILib FrankenCode shortcut
        $shortcutPath = Join-Path $desktopPath "WPILib FrankenCode $year.lnk"
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $frankenLauncher
        $shortcut.WorkingDirectory = $frcCodeDir
        $shortcut.Description = "Launch VS Code with WPILib $year environment"
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
                # Look for tool executables
                $toolExes = Get-ChildItem $toolsDir -Filter "*.exe" -ErrorAction SilentlyContinue
                $toolBats = Get-ChildItem $toolsDir -Filter "*.bat" -ErrorAction SilentlyContinue
                $toolVbs = Get-ChildItem $toolsDir -Filter "*.vbs" -ErrorAction SilentlyContinue

                # Create a Start Menu folder for WPILib tools
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

    # ── Add frccode to system PATH (optional but helpful) ──
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
    # Created regardless of gh auth status — ready when auth is set up

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

    # frc-ai.ps1  — PowerShell version
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

    # frc-explain.ps1  — PowerShell version
    $frcExplainPs1 = Join-Path $frcCodeDir "frc-explain.ps1"
    @"
# WPILib FRC Explain (PowerShell)
# Explains a shell command or WPILib concept using gh copilot explain.
# Usage:  .\frc-explain.ps1 'command or concept'
param([Parameter(ValueFromRemainingArguments)][string[]]`$Item)

`$wpilibHome = Join-Path `$PSScriptRoot '..'
`$env:JAVA_HOME = Join-Path `$wpilibHome 'jdk'
`$env:PATH = "`$env:JAVA_HOME\bin;`$env:PATH"

`$q = `$Item -join ' '
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
    # Teams copy this to <robot-project>/.github/copilot-instructions.md
    # GitHub Copilot (VS Code, CLI, web) reads it as permanent project context.
    $instructionsPath = Join-Path $yearDir "wpilib-copilot-instructions.md"
    @"
# WPILib FRC Robot Code — GitHub Copilot Instructions

This repository contains FRC (FIRST Robotics Competition) robot code using WPILib $year.

## Project Overview
- **Build system**: Gradle with the GradleRIO plugin
- **Target hardware**: NI roboRIO running Java (or C++)
- **WPILib version**: $($script:Config.Version)
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
  JAVA_HOME should point to ``C:/Users/Public/wpilib/$year/jdk``
- Use ``RobotBase.isSimulation()`` to swap in simulated hardware

## Copilot AI Shortcuts (from terminal, after WPILib FrankenCode install)
``````bash
frc-ai "how do I add a subsystem"          # gh copilot suggest with WPILib context
frc-ai "deploy command for team 1234"      # direct question
frc-explain "./gradlew deploy -Pteam=1234" # explain a gradle command
``````
"@ | Set-Content $instructionsPath -Encoding UTF8
    Write-Step "Created template: $instructionsPath" "OK"
    Write-Step "  Copy to <robot-project>/.github/copilot-instructions.md" "INFO"
    Write-Step "  Primes GitHub Copilot (VS Code + CLI + web) with WPILib context" "INFO"

    # ── Summary ──
    Write-Host ""
    Write-SectionHeader "Copilot CLI — WPILib Integration Summary"
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
# PHASE 9: VERIFICATION
# ─────────────────────────────────────────────────────────────────────────────

function Test-Installation {
    Write-Banner "Phase 9: Installation Verification"

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

    # ── JDK 17 (builds) ──
    $javaExe = Join-Path $yearDir "jdk\bin\java.exe"
    $javaPresent = Test-Path $javaExe
    $javaDetail = ""
    if ($javaPresent) {
        $javaDetail = (& $javaExe -version 2>&1 | Select-Object -First 1) -replace '"', ''
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

    # ── roboRIO Toolchain ──
    $toolchainPresent = Test-Path (Join-Path $yearDir "roborio")
    $gccPath = Get-ChildItem (Join-Path $yearDir "roborio") -Filter "arm-frc*-g++*" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    Add-TestResult "roboRIO C++ toolchain" $toolchainPresent $(if ($gccPath) { $gccPath.Name })

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
    Add-TestResult "C/C++ extension" ($cppExt.Count -gt 0)

    $javaExt = @($extensions -match "redhat.java")
    Add-TestResult "Java Language extension" ($javaExt.Count -gt 0)

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
    Add-TestResult "Desktop tools" $toolsPresent "$toolCount executables/scripts"

    # ── AdvantageScope ──
    $asPresent = Test-Path (Join-Path $yearDir "advantagescope")
    Add-TestResult "AdvantageScope" $asPresent

    # ── Elastic Dashboard ──
    $elasticPresent = Test-Path (Join-Path $yearDir "elastic")
    Add-TestResult "Elastic Dashboard" $elasticPresent

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
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ─────────────────────────────────────────────────────────────────────────────

function Main {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Banner "WPILib FrankenCode Installer v1.1.0"
    Write-Step "WPILib Version: $($script:Config.Version)" "INFO"
    Write-Step "Season Year: $($script:Config.Year)" "INFO"
    Write-Step "Install Dir: $($script:Config.YearDir)" "INFO"
    Write-Step "Download Dir: $($script:Config.DownloadDir)" "INFO"
    Write-Host ""

    # Phase 0: Prerequisites
    Test-Prerequisites

    # Phase 1: Download ISO
    $isoPath = Get-WPILibISO

    # Phase 2: Mount & Extract
    Install-FromISO -IsoPath $isoPath

    # Phase 2B: JDK 21 for VS Code Java Language Server
    Install-Jdk21LanguageServer

    # Phase 3: Gradle Cache
    Install-GradleCache

    # Phase 4: Tools & Maven
    Install-ToolsAndMaven

    # Phase 5: VS Code Extensions
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

    Write-Banner "Installation Complete!"
    Write-Step "Total time: $($elapsed.ToString('hh\:mm\:ss'))" "INFO"
    Write-Step "" "INFO"
    Write-Step "Next steps:" "INFO"
    Write-Step "  1. Restart VS Code to activate extensions" "INFO"
    Write-Step "  2. Press Ctrl+Shift+P → type 'WPILib' → verify commands appear" "INFO"
    Write-Step "  3. Create a new project: 'WPILib: Create a new project'" "INFO"
    Write-Step "  4. Build: 'WPILib: Build Robot Code'" "INFO"
    Write-Step "" "INFO"
    Write-Step "FrankenCode launcher: $($script:Config.YearDir)\frccode\FrankenCode$($script:Config.Year).cmd" "INFO"
    Write-Step "Desktop shortcut: 'WPILib FrankenCode $($script:Config.Year)'" "INFO"
}

# Run!
Main
