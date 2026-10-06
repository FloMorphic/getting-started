#Requires -Version 5.1
<#
    FloMorphic one-liner installer for Windows.

      irm https://raw.githubusercontent.com/FloMorphic/getting-started/main/install.ps1 | iex

    FloMorphic — like every Inflowenger product — runs as Docker containers, and
    Docker on Windows means Docker Desktop on the WSL 2 backend. So this script is
    not a port of install.sh: it is the part install.sh cannot do. It prepares the
    HOST (WSL 2, a Linux distro, Docker Desktop, the engine actually reachable from
    inside that distro), asking before it installs anything, and then runs the one
    and only installer — install.sh, inside WSL — so Windows and Linux end up with
    the same stack from the same source of truth.

    What it does, in order:
      1. checks Windows build / architecture / virtualization
      2. WSL 2        — installs it (with your consent) if missing, picks a distro,
                        installs Ubuntu if there is none, upgrades a WSL 1 distro
      3. Docker Desktop — installs it (with your consent) if missing, starts it,
                        waits for the engine, turns on WSL integration for the distro
      4. runs install.sh inside the distro, forwarding every FLOMORPHIC_* / platform
         env var you set in PowerShell

    Installing WSL and Docker Desktop needs administrator rights; the script asks
    before relaunching itself elevated. A fresh WSL install usually needs a reboot —
    it will tell you, and you re-run the same one-liner afterwards.

    Parameters (a plain `irm | iex` takes none — use the scriptblock form below,
    or the env vars, which work with either):

      -Yes                 accept every prompt, install what is missing, no questions
                           (env: ASSUME_YES=1)
      -Distro <name>       WSL distro to install into      (env: WSL_DISTRO)
                           default: the default distro, else the first usable one,
                           else Ubuntu is installed
      -InstallDir <path>   install directory INSIDE the distro (env: FLOMORPHIC_DIR)
                           default: ~/flomorphic in the distro's home
      -Ref <branch|tag>    ref install.sh is fetched from   (env: REPO_REF, default main)
      -NoInstall           check and report only; never install WSL or Docker Desktop
      -Help                print this header

      & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FloMorphic/getting-started/main/install.ps1))) -Yes

    Everything install.sh understands (FLOMORPHIC_PORT, PLATFORM_MODE, API_JWT_SECRET,
    IMAGE_TAG, EULA_ACCEPT, ...) is set as a normal PowerShell env var before running
    this script and is forwarded into the distro:

      $env:FLOMORPHIC_PORT = '9000'; $env:ASSUME_YES = '1'
      irm https://raw.githubusercontent.com/FloMorphic/getting-started/main/install.ps1 | iex

    Docker Desktop is Docker Inc.'s product under its own licence (free for personal
    use, small businesses and education; a paid subscription for larger companies —
    https://docs.docker.com/subscription/desktop-license/). This script only installs
    it at your request; it is not part of FloMorphic.
#>
[CmdletBinding()]
param(
  [switch] $Yes,
  [string] $Distro,
  [string] $InstallDir,
  [string] $Ref,
  [switch] $NoInstall,
  [switch] $Help
)

# ── product config — the only block that differs between the three installers ──
$PRODUCT        = 'FloMorphic'
$TAGLINE        = 'canvas + API + builtin plugin nodes, on the Inflowenger runtime'
$REPO_SLUG      = 'FloMorphic/getting-started'
$INSTALLER_SH   = 'install.sh'
$DEFAULT_SUBDIR = 'flomorphic'            # install dir created in the distro's home
$STACK_SUBDIR   = 'flomorphic'            # compose stack install.sh writes under it
$DIR_VAR        = 'FLOMORPHIC_DIR'        # the install-dir env var install.sh reads
$SELF_URL       = "https://raw.githubusercontent.com/$REPO_SLUG/main/install.ps1"
# Env vars install.sh reads; forwarded into WSL when set in this PowerShell session.
$FORWARD_VARS   = @(
  'FLOMORPHIC_DIR', 'PLATFORM_MODE', 'INFLOW_INFRA_API', 'PLUGIN_INFRA_URL',
  'INFRA_API_PORT', 'INFRA_NATS_PORT', 'API_JWT_SECRET', 'FRACTAL_TAGS',
  'FRACTAL_NAME', 'INSTALL_INSPECTOR', 'IMAGE_NS', 'IMAGE_TAG',
  'FLOMORPHIC_IMAGE', 'FLOMORPHIC_PORT', 'FLOMORPHIC_API_PORT',
  'PLUGINS_ENABLED', 'AUTH_ENABLED', 'REPO_RAW', 'REPO_REF',
  'PLATFORM_INSTALLER', 'ASSUME_YES', 'EULA_ACCEPT', 'EULA_URL'
)
# Why the install dir belongs in the Linux filesystem, in this product's terms.
$STATE_NOTE     = @(
  'The stack keeps a SQLite database in a bind mount, and SQLite over the',
  'Windows-filesystem bridge (/mnt/c) is slow and prone to locking errors.'
)
# Printed in the closing summary; the ports install.sh publishes to the host.
$SUMMARY_PORTS  = @(
  @{ Label = 'Canvas';               Var = 'FLOMORPHIC_PORT';      Default = '8088' },
  @{ Label = 'API';                  Var = 'FLOMORPHIC_API_PORT';  Default = '8026' }
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # a visible progress bar breaks `irm | iex` output

# ── pretty output ─────────────────────────────────────────────────────────────
# Write-Host, not ANSI: this has to look the same in Windows PowerShell 5.1's
# console (no VT by default), in Windows Terminal and in a piped transcript.
function Step { param([string]$m) Write-Host ''; Write-Host '==> ' -ForegroundColor Cyan -NoNewline; Write-Host $m }
function Info { param([string]$m) Write-Host "    $m" }
function Ok   { param([string]$m) Write-Host '    ' -NoNewline; Write-Host '[ok] ' -ForegroundColor Green -NoNewline; Write-Host $m }
function Warn { param([string]$m) Write-Host '    ' -NoNewline; Write-Host '[!]  ' -ForegroundColor Yellow -NoNewline; Write-Host $m }

# Stopping, when the script may have arrived through `irm | iex`.
#
# `exit` is not usable here. Under Invoke-Expression it terminates the caller's
# whole PowerShell session — verified, in every form: at top level, inside & { },
# and inside a function — which closes the user's window with the error still
# unread. So stopping is a throw that the wrapper at the bottom of this file
# catches, and $script:StopCode carries the status a file run should exit with.
$script:StopCode = 0
$STOP = 'INSTALLER_STOP:'
function Die  { param([string]$m) $script:StopCode = 1; throw ($STOP + $m) }
function Quit { param([int]$Code = 0) $script:StopCode = $Code; throw $STOP }

# Everything below runs inside this try; the catch at the end of the file turns a
# Die/Quit back into a printed message and an exit status. Deliberately not
# re-indented, so this stays a two-line wrapper rather than a rewrite.
try {

if ($Help) {
  if ($PSCommandPath) {
    foreach ($line in (Get-Content -LiteralPath $PSCommandPath)) {
      if ($line -match '^\s*<#') { continue }
      if ($line -match '^\s*#>') { break }
      Write-Host $line
    }
  } else { Info "see https://github.com/$REPO_SLUG#install" }
  Quit 0
}

# ── settings: parameters, then env vars, then defaults ────────────────────────
function EnvOr { param([string]$name, $fallback) $v = [Environment]::GetEnvironmentVariable($name); if ([string]::IsNullOrWhiteSpace($v)) { $fallback } else { $v } }

$AssumeYes = $Yes.IsPresent -or (EnvOr 'ASSUME_YES' '0') -eq '1'
if (-not $Distro)     { $Distro     = EnvOr 'WSL_DISTRO' '' }
if (-not $InstallDir) { $InstallDir = EnvOr $DIR_VAR '' }
if (-not $Ref)        { $Ref        = EnvOr 'REPO_REF' 'main' }

$RepoRaw     = EnvOr 'REPO_RAW' "https://raw.githubusercontent.com/$REPO_SLUG"
$InstallerUrl = "$RepoRaw/$Ref/$INSTALLER_SH"

# A console we can prompt at. `irm | iex` keeps stdin attached, so Read-Host works;
# a scheduled/redirected run has none, and then every prompt takes its default.
function Have-Tty { (-not $AssumeYes) -and -not [Console]::IsInputRedirected -and $Host.UI.RawUI }

function Ask {  # <prompt> <default> -> string
  param([string]$Prompt, [string]$Default = '')
  if (-not (Have-Tty)) { return $Default }
  $hint = if ($Default) { " [$Default]" } else { '' }
  Write-Host ''
  Write-Host "    $Prompt$hint" -ForegroundColor White -NoNewline
  $reply = Read-Host
  if ([string]::IsNullOrWhiteSpace($reply)) { $Default } else { $reply.Trim() }
}

function Confirm-Step {  # <prompt> <default y|n> -> bool
  param([string]$Prompt, [string]$Default = 'n')
  if (-not (Have-Tty)) { return ($Default -eq 'y') }
  $hint = if ($Default -eq 'y') { '[Y/n]' } else { '[y/N]' }
  Write-Host ''
  Write-Host "    $Prompt $hint" -ForegroundColor White -NoNewline
  $reply = Read-Host
  if ([string]::IsNullOrWhiteSpace($reply)) { $reply = $Default }
  return ($reply.Trim() -match '^[Yy]')
}

function Pause-Here { param([string]$m = 'Press Enter when you are done') if (Have-Tty) { Write-Host ''; Write-Host "    $m" -ForegroundColor White -NoNewline; [void](Read-Host) } }

# ── wsl.exe plumbing ──────────────────────────────────────────────────────────
# wsl.exe speaks UTF-16LE unless told otherwise, which turns every captured line
# into NUL-riddled mush. WSL_UTF8 is the documented fix; the filter below covers
# wsl.exe builds that predate it.
$env:WSL_UTF8 = '1'

$WslExe = if ($env:SystemRoot) { Join-Path $env:SystemRoot 'System32\wsl.exe' } else { $null }
if (-not $WslExe -or -not (Test-Path -LiteralPath $WslExe)) {
  $cmd = Get-Command wsl.exe -ErrorAction SilentlyContinue
  if ($cmd) { $WslExe = $cmd.Source } else { $WslExe = $null }
}

function Wsl-Raw {  # run wsl.exe, capture stdout+stderr, never throw
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$WslArgs)
  if (-not $WslExe) { return [pscustomobject]@{ Code = 127; Out = 'wsl.exe not found' } }
  $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    $out = & $WslExe @WslArgs 2>&1 | ForEach-Object { ($_ -replace "`0", '').Trim() }
    [pscustomobject]@{ Code = $LASTEXITCODE; Out = (($out | Where-Object { $_ }) -join "`n") }
  } finally { $ErrorActionPreference = $prevEap }
}

# Everything that runs inside the distro goes through here. Single quotes only in
# $Bash: Windows PowerShell 5.1 mangles embedded double quotes when it hands an
# argument to a native .exe, and a mangled command is a confusing failure.
function Wsl-Bash {  # <bash command> [-Distro x] [-AsRoot] -> {Code, Out}
  param([Parameter(Mandatory)][string]$Bash, [string]$InDistro = $Distro, [switch]$AsRoot)
  if ($Bash -match '"') { Die 'internal: double quote in a WSL command (see Wsl-Bash)' }
  $a = @()
  if ($InDistro) { $a += @('-d', $InDistro) }
  if ($AsRoot)   { $a += @('-u', 'root') }
  $a += @('--', 'bash', '-lc', $Bash)
  Wsl-Raw @a
}

# Interactive pass-through, for the commands that have to be able to ask the user
# something — install.sh's own prompts, sudo's password.
#
# Nothing here may be captured. PowerShell only hands a native command the real
# console handles when its output is NOT being consumed; the moment it is (assigned
# to a variable, piped to a cmdlet), wsl.exe gets a pipe instead of a console, does
# not allocate a pty, and every prompt install.sh writes to /dev/tty vanishes along
# with the answer. So this function returns nothing and leaves the exit code in
# $script:WslExitCode for the caller to read.
$script:WslExitCode = 0
function Wsl-Interactive {  # <bash command> -> () , sets $script:WslExitCode
  param([Parameter(Mandatory)][string]$Bash, [string]$InDistro = $Distro)
  if ($Bash -match '"') { Die 'internal: double quote in a WSL command (see Wsl-Interactive)' }
  $a = @()
  if ($InDistro) { $a += @('-d', $InDistro) }
  $a += @('--', 'bash', '-lc', $Bash)
  & $WslExe @a
  $script:WslExitCode = $LASTEXITCODE
}

function Sh-Quote { param([string]$s) "'" + ($s -replace "'", "'\''") + "'" }   # POSIX single-quoting

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Re-run this very script elevated. From a file we relaunch the file; from
# `irm | iex` there is no file, so the new window re-fetches the same URL —
# which is why $SELF_URL is a constant and not derived from anything.
function Invoke-Elevated {
  param([string]$Why)
  Step 'Administrator rights needed'
  Info $Why
  Info 'Windows will ask for consent (UAC), then continue in a new elevated window.'
  if (-not (Confirm-Step 'Relaunch this installer as administrator?' 'y')) {
    Warn 'Not elevated. Re-run this one-liner from an elevated PowerShell to continue:'
    Info "  irm $SELF_URL | iex"
    Quit 1
  }
  $fwd = @()
  foreach ($n in ($FORWARD_VARS + @('WSL_DISTRO'))) {
    $v = [Environment]::GetEnvironmentVariable($n)
    if (-not [string]::IsNullOrWhiteSpace($v)) { $fwd += ('$env:{0} = {1}' -f $n, ("'" + ($v -replace "'", "''") + "'")) }
  }
  if ($AssumeYes) { $fwd += '$env:ASSUME_YES = ' + "'1'" }
  $prelude = ($fwd -join '; ')
  if ($PSCommandPath) {
    $run = "& '" + ($PSCommandPath -replace "'", "''") + "'"
    if ($Distro)     { $run += " -Distro '"     + ($Distro     -replace "'", "''") + "'" }
    if ($InstallDir) { $run += " -InstallDir '" + ($InstallDir -replace "'", "''") + "'" }
    if ($Ref)        { $run += " -Ref '"        + ($Ref        -replace "'", "''") + "'" }
    if ($AssumeYes)  { $run += ' -Yes' }
  } else {
    $run = "irm '$SELF_URL' | iex"
  }
  $inner = if ($prelude) { "$prelude; $run" } else { $run }
  $psExe = (Get-Process -Id $PID).Path
  if (-not $psExe) { $psExe = 'powershell.exe' }
  Start-Process -FilePath $psExe -Verb RunAs -ArgumentList @(
    '-NoExit', '-ExecutionPolicy', 'Bypass', '-NoProfile', '-Command', $inner
  ) | Out-Null
  Info 'Continue in the elevated window; this one is done.'
  Quit 0
}

# ══ banner ════════════════════════════════════════════════════════════════════
Write-Host ''
Write-Host "  $PRODUCT installer for Windows" -ForegroundColor White
Write-Host "  $TAGLINE" -ForegroundColor DarkGray
Write-Host '  Docker is the engine, WSL 2 is where it runs — this gets both in place first.' -ForegroundColor DarkGray

# ══ 1. the host ═══════════════════════════════════════════════════════════════
Step 'Checking Windows'

if ($env:OS -ne 'Windows_NT') { Die 'this script is the Windows installer — on Linux or macOS run install.sh instead.' }
if ($PSVersionTable.PSVersion.Major -lt 5) { Die "PowerShell 5.1+ required (found $($PSVersionTable.PSVersion))." }

$os    = Get-CimInstance Win32_OperatingSystem
$build = [int]($os.BuildNumber)
$arch  = $env:PROCESSOR_ARCHITECTURE
Info "$($os.Caption) build $build, $arch"

# `wsl --install` (one command, no DISM, no reboot dance) landed in 2004 / 19041.
# Older builds can run WSL 2, but only through a manual feature + kernel install
# that no installer should be doing on a user's behalf.
if ($build -lt 19041) {
  Die @"
Windows 10 2004 (build 19041) or newer is needed for WSL 2 and Docker Desktop.
This machine is build $build. Update Windows, then re-run this installer.
  Docker Desktop requirements: https://docs.docker.com/desktop/install/windows-install/
"@
}
if ($arch -notin @('AMD64', 'ARM64')) { Die "unsupported architecture '$arch' — Docker Desktop needs x64 or ARM64." }
if ($arch -eq 'ARM64') { Warn 'ARM64: the images are multi-arch, so this works — ARM is simply less travelled.' }
Ok 'Windows build and architecture are fine'

# Virtualization off in firmware is THE classic WSL 2 failure, and its symptom is
# an opaque error several minutes later. Warn now instead.
try {
  $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
  if ($cpu.PSObject.Properties['VirtualizationFirmwareEnabled'] -and $cpu.VirtualizationFirmwareEnabled -eq $false) {
    Warn 'Hardware virtualization looks disabled in firmware (BIOS/UEFI).'
    Warn 'WSL 2 cannot start without it — enable Intel VT-x / AMD-V if the steps below fail.'
  }
} catch { }

# ══ 2. WSL 2 ══════════════════════════════════════════════════════════════════
Step 'Checking WSL 2'

# Distros Docker Desktop manages for itself. They are not general-purpose: they
# have no package manager and no user, so the installer cannot run in them.
$DockerOwnedDistros = @('docker-desktop', 'docker-desktop-data', 'docker-desktop-proxy')

function Get-WslDistros {
  # -> [{ Name, Version, Default }] ; empty when WSL is absent or has no distro
  $r = Wsl-Raw '--list' '--verbose'
  if ($r.Code -ne 0 -or -not $r.Out) { return @() }
  $rows = @()
  foreach ($line in ($r.Out -split "`n")) {
    $l = $line.Trim()
    if (-not $l) { continue }
    if ($l -match '^\*?\s*NAME\s') { continue }           # header, any locale that keeps NAME
    $isDefault = $l.StartsWith('*')
    $l = $l.TrimStart('*').Trim()
    $parts = $l -split '\s+'
    if ($parts.Count -lt 1) { continue }
    $ver = if ($parts.Count -ge 3) { $parts[-1] } else { '' }
    $rows += [pscustomobject]@{ Name = $parts[0]; Version = $ver; Default = $isDefault }
  }
  # A localised header has no NAME column to skip; a row whose version is not a
  # number is that header, not a distro.
  $rows | Where-Object { $_.Version -match '^\d+$' -or $_.Version -eq '' }
}

function Get-UsableDistros { Get-WslDistros | Where-Object { $DockerOwnedDistros -notcontains $_.Name } }

# WSL actually runs: the feature is on, the kernel is there, lxss answers.
function Test-WslWorks {
  if ((Wsl-Raw '--status').Code -eq 0) { return $true }
  # Older wsl.exe has no --status. --list exits non-zero when there is no distro,
  # so a zero here proves WSL works but a non-zero proves nothing on its own.
  (Wsl-Raw '--list' '--quiet').Code -eq 0
}

# WSL is installed, whether or not it can run yet (no distro, or a reboot pending).
# The service only exists once the feature/MSIX is in place, and reading it needs
# no elevation — unlike Get-WindowsOptionalFeature.
function Test-WslPresent {
  [bool](Get-Service -Name 'LxssManager', 'WslService' -ErrorAction SilentlyContinue)
}

$distros = @()
# "Installed but with no distro yet" must not be read as "WSL is missing", or the
# next step reinstalls the feature and then asks for a reboot that changes nothing.
$wslInstalled = $WslExe -and ((Test-WslWorks) -or (Test-WslPresent))
if ($wslInstalled) { $distros = @(Get-UsableDistros) }

if (-not $wslInstalled) {
  Info 'WSL is not installed (or not enabled) on this machine.'
  Info 'WSL 2 is Microsoft''s Linux kernel for Windows. Docker Desktop runs its engine'
  Info "inside it, and $PRODUCT runs inside Docker — so it is not optional here."
  Info 'It is installed with: wsl --install  (a Windows feature, from Microsoft)'
  if ($NoInstall) { Die 'WSL is missing and -NoInstall was given. Run `wsl --install` yourself, then re-run.' }
  if (-not (Confirm-Step 'Install WSL 2 now? (needs administrator, usually a reboot)' 'y')) {
    Die 'WSL is required: run `wsl --install` in an elevated PowerShell, reboot, then re-run this script.'
  }
  if (-not (Test-Admin)) { Invoke-Elevated 'Installing the WSL 2 Windows feature requires administrator rights.' }

  Step 'Installing WSL 2'
  Info 'wsl --install --no-distribution  (the distro is chosen in the next step)'
  $r = Wsl-Raw '--install' '--no-distribution'
  if ($r.Code -ne 0) {
    # Pre-22H2 wsl.exe has no --no-distribution; its plain --install pulls Ubuntu too.
    Info 'retrying with: wsl --install'
    $r = Wsl-Raw '--install'
  }
  if ($r.Out) { $r.Out -split "`n" | ForEach-Object { Info $_ } }
  Wsl-Raw '--set-default-version' '2' | Out-Null

  # Strict here: the feature now exists either way, so only a working WSL means
  # we can carry on without a restart.
  if (-not (Test-WslWorks)) {
    Step 'Reboot required'
    Info 'The WSL feature is installed but Windows has to restart before it can run.'
    Info 'After the reboot, run exactly the same one-liner again and it will carry on:'
    Info "  irm $SELF_URL | iex"
    if (Confirm-Step 'Restart Windows now?' 'n') { Restart-Computer -Force; Quit 0 }
    Quit 0
  }
  Ok 'WSL 2 is installed'
  $distros = @(Get-UsableDistros)
}

# Kernel updates are independent of the feature; an old kernel breaks Docker
# Desktop with its own distinct error. Cheap to do, so just do it.
if (Test-Admin) { Wsl-Raw '--update' | Out-Null }

# ── pick (or install) the distro the product is installed from ────────────────
if ($Distro) {
  if (-not ($distros | Where-Object { $_.Name -eq $Distro })) {
    if (@(Get-WslDistros | Where-Object { $_.Name -eq $Distro }).Count -gt 0) {
      Die "'$Distro' is a Docker Desktop internal distro — pick a real Linux distro (e.g. Ubuntu)."
    }
    Die "WSL distro '$Distro' is not installed. Installed: $((@(Get-UsableDistros).Name) -join ', ')"
  }
} elseif ($distros.Count -gt 0) {
  $pick = $distros | Where-Object { $_.Default } | Select-Object -First 1
  if (-not $pick) { $pick = $distros | Select-Object -First 1 }
  $Distro = $pick.Name
  Ok "using WSL distro: $Distro$(if ($distros.Count -gt 1) { " (of: $((@($distros).Name) -join ', '))" })"
} else {
  Info 'WSL is installed but there is no Linux distro to install into.'
  Info 'Ubuntu is the default choice: it is what install.sh is tested on.'
  if ($NoInstall) { Die 'no WSL distro and -NoInstall was given. Run `wsl --install -d Ubuntu`, then re-run.' }
  if (-not (Confirm-Step 'Install Ubuntu into WSL now?' 'y')) { Die 'a Linux distro is required.' }

  Step 'Installing Ubuntu'
  Info 'Ubuntu will open its first-run setup and ask you to choose a UNIX username'
  Info 'and password. That account is local to the distro — it is not a Windows or'
  Info 'Microsoft account, and the password is what `sudo` will ask for.'
  $r = Wsl-Raw '--install' '-d' 'Ubuntu'
  if ($r.Out) { $r.Out -split "`n" | ForEach-Object { Info $_ } }
  if ($r.Code -ne 0) {
    Warn 'wsl --install -d Ubuntu did not finish cleanly.'
    Info 'Install it from the Microsoft Store (search: Ubuntu), launch it once, then re-run this script.'
    Die 'could not install the distro automatically.'
  }
  Pause-Here 'Finish the Ubuntu setup (username + password), then press Enter here'
  $distros = @(Get-UsableDistros)
  $pick = $distros | Where-Object { $_.Name -like 'Ubuntu*' } | Select-Object -First 1
  if (-not $pick) { $pick = $distros | Select-Object -First 1 }
  if (-not $pick) { Die 'still no usable WSL distro — install Ubuntu from the Microsoft Store and re-run.' }
  $Distro = $pick.Name
  Ok "distro ready: $Distro"
}

# Docker Desktop's engine is only reachable from a WSL 2 distro; a WSL 1 distro
# has no docker at all, with no hint as to why.
$distroRow = Get-WslDistros | Where-Object { $_.Name -eq $Distro } | Select-Object -First 1
if ($distroRow -and $distroRow.Version -eq '1') {
  Warn "'$Distro' runs on WSL 1, where Docker Desktop's engine is not reachable."
  if ($NoInstall) { Die "convert it yourself: wsl --set-version $Distro 2" }
  if (Confirm-Step "Convert '$Distro' to WSL 2 now? (it keeps your files; takes a few minutes)" 'y') {
    Info "wsl --set-version $Distro 2"
    $r = Wsl-Raw '--set-version' $Distro '2'
    if ($r.Out) { $r.Out -split "`n" | ForEach-Object { Info $_ } }
    if ($r.Code -ne 0) { Die "conversion failed. Run it by hand: wsl --set-version $Distro 2" }
    Ok "$Distro is now WSL 2"
  } else { Die "a WSL 2 distro is required (wsl --set-version $Distro 2)." }
}

# The distro has to actually boot — a half-finished first-run setup looks
# installed in --list and fails on the first real command.
$probe = Wsl-Bash 'echo wsl-ok'
if ($probe.Code -ne 0 -or $probe.Out -notmatch 'wsl-ok') {
  Warn "'$Distro' did not answer a simple command:"
  if ($probe.Out) { $probe.Out -split "`n" | ForEach-Object { Info $_ } }
  Info "Open it once from the Start menu (or run: wsl -d $Distro), finish any first-run"
  Info 'setup it shows, then re-run this installer.'
  Die "the WSL distro '$Distro' is not usable yet."
}
$WslUser = (Wsl-Bash 'id -un').Out
Ok "WSL 2 distro '$Distro' is up (default user: $WslUser)"

# ══ 3. Docker Desktop ═════════════════════════════════════════════════════════
Step 'Checking Docker Desktop'

# Docker Desktop's own install locations. Join-Path throws on a null base, and
# ProgramFiles(x86) is not guaranteed to be set (notably on ARM64), so the bases
# are filtered before they are joined.
function Find-DockerDesktop {
  $bases = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, 'C:\Program Files') | Where-Object { $_ }
  foreach ($b in ($bases | Select-Object -Unique)) {
    $p = Join-Path $b 'Docker\Docker\Docker Desktop.exe'
    if (Test-Path -LiteralPath $p) { return $p }
  }
  return $null
}

$DockerDesktopExe = Find-DockerDesktop

function Test-DockerEngine {
  # The engine is up when it answers from INSIDE the distro — that, not the
  # Windows `docker` command, is what install.sh will be using.
  (Wsl-Bash 'docker info > /dev/null 2>&1 && echo engine-ok').Out -match 'engine-ok'
}
function Test-DockerCliInWsl { (Wsl-Bash 'command -v docker > /dev/null 2>&1 && echo cli-ok').Out -match 'cli-ok' }

function Start-DockerDesktop {
  if (-not $DockerDesktopExe) { return $false }
  if (Get-Process 'Docker Desktop' -ErrorAction SilentlyContinue) { return $true }
  Info 'Starting Docker Desktop...'
  try { Start-Process -FilePath $DockerDesktopExe | Out-Null; return $true } catch { Warn "could not start Docker Desktop: $($_.Exception.Message)"; return $false }
}

function Wait-DockerEngine {
  param([int]$TimeoutSec = 300)
  Info "Waiting for the Docker engine (up to $([int]($TimeoutSec / 60)) min)..."
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    if (Test-DockerEngine) { return $true }
    Start-Sleep -Seconds 5
  }
  return $false
}

if (-not $DockerDesktopExe) {
  Info 'Docker Desktop is not installed on this machine.'
  Info "Everything $PRODUCT ships is a container, so the Docker engine has to live on"
  Info 'the host. On Windows that is Docker Desktop with the WSL 2 backend.'
  Info 'Licence: free for personal use, education and small businesses; larger'
  Info 'companies need a paid subscription — https://docs.docker.com/subscription/desktop-license/'
  if ($NoInstall) { Die 'Docker Desktop is missing and -NoInstall was given. Install it, then re-run.' }
  if (-not (Confirm-Step 'Install Docker Desktop now? (needs administrator)' 'y')) {
    Die 'Docker Desktop is required. Install it from https://docs.docker.com/desktop/install/windows-install/ and re-run.'
  }
  if (-not (Test-Admin)) { Invoke-Elevated 'Installing Docker Desktop requires administrator rights.' }

  Step 'Installing Docker Desktop'
  $installed = $false
  $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
  if ($winget) {
    Info 'winget install --id Docker.DockerDesktop --exact'
    & $winget.Source install --id Docker.DockerDesktop --exact --accept-package-agreements --accept-source-agreements --disable-interactivity
    # 0 = installed, -1978335189 = already installed, 0x3010/3010 = reboot wanted
    if ($LASTEXITCODE -in @(0, -1978335189, 3010, -1978335216)) { $installed = $true }
    else { Warn "winget exited with $LASTEXITCODE — falling back to the direct download." }
  } else {
    Info 'winget is not available; downloading the installer from docker.com instead.'
  }

  if (-not $installed) {
    $dlArch = if ($arch -eq 'ARM64') { 'arm64' } else { 'amd64' }
    $url    = "https://desktop.docker.com/win/main/$dlArch/Docker%20Desktop%20Installer.exe"
    $exe    = Join-Path $env:TEMP 'DockerDesktopInstaller.exe'
    Info "Downloading $url"
    try { Invoke-WebRequest -Uri $url -OutFile $exe -UseBasicParsing } catch { Die "download failed: $($_.Exception.Message)" }
    Info 'Running the installer (quiet, this takes a few minutes)...'
    $p = Start-Process -FilePath $exe -ArgumentList @('install', '--accept-license', '--quiet', '--backend=wsl-2') -Wait -PassThru
    if ($p.ExitCode -notin @(0, 3010)) { Die "the Docker Desktop installer exited with $($p.ExitCode)." }
    Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue
    $installed = $true
  }

  $DockerDesktopExe = Find-DockerDesktop
  if (-not $DockerDesktopExe) {
    Warn 'Docker Desktop was installed but its executable is not where it was expected.'
    Info 'Start it from the Start menu, then re-run this installer.'
    Die 'cannot locate Docker Desktop.'
  }
  Ok 'Docker Desktop installed'

  # Installing adds the current user to docker-users; that group membership is
  # only read at logon, so the very first run can refuse to start.
  Warn 'If Docker Desktop refuses to start, sign out of Windows and back in once'
  Warn '(its installer puts your account in the "docker-users" group at install time).'
} else {
  Ok "Docker Desktop found: $DockerDesktopExe"
}

if (-not (Test-DockerEngine)) {
  Start-DockerDesktop | Out-Null
  Info 'On its first run Docker Desktop shows a licence/terms dialog and takes a'
  Info 'few minutes to start its engine. Accept it if it appears.'
  if (-not (Wait-DockerEngine -TimeoutSec 300)) {
    # Reachable from Windows but not from the distro = integration is off. That is
    # the single most common Docker-Desktop-on-WSL failure, so it gets its own path.
    # Docker Desktop installed in THIS session is not on this process's PATH, so
    # its own bin directory is checked too rather than trusting PATH alone.
    $winDockerPath = (Get-Command docker.exe -ErrorAction SilentlyContinue).Source
    if (-not $winDockerPath -and $DockerDesktopExe) {
      $cand = Join-Path (Split-Path -Parent $DockerDesktopExe) 'resources\bin\docker.exe'
      if (Test-Path -LiteralPath $cand) { $winDockerPath = $cand }
    }
    $winEngineUp = $false
    if ($winDockerPath) { & $winDockerPath info *> $null; $winEngineUp = ($LASTEXITCODE -eq 0) }

    if ($winEngineUp -and -not (Test-DockerCliInWsl)) {
      Step 'Docker Desktop: WSL integration is off for this distro'
      Info "The engine is running on Windows but '$Distro' cannot see it, so the"
      Info 'installer inside WSL would not find docker.'
      Info 'Turn it on:  Docker Desktop -> Settings -> Resources -> WSL integration'
      Info "             enable '$Distro' (or 'Enable integration with my default WSL distro')"
      Info '             -> Apply & restart'
      # Docker Desktop's default is the DEFAULT distro only, so a non-default one
      # is off until it is named — or made the default.
      if (-not ($distroRow -and $distroRow.Default)) {
        Info "             '$Distro' is not your default distro, so the default-distro"
        Info "             checkbox will not cover it: either tick '$Distro' itself,"
        Info "             or make it the default with  wsl --set-default $Distro"
      }
      Pause-Here 'Press Enter once WSL integration is enabled'
      if (-not (Wait-DockerEngine -TimeoutSec 180)) {
        Die "docker is still not reachable from '$Distro'. Check Docker Desktop -> Settings -> Resources -> WSL integration."
      }
    } else {
      Warn 'The Docker engine did not come up in time.'
      Info 'Open Docker Desktop, let it finish starting (and accept its terms), then re-run this installer.'
      Info "If it is already running, check: Settings -> General -> 'Use the WSL 2 based engine'"
      Info "                           and: Settings -> Resources -> WSL integration -> '$Distro'"
      Die 'the Docker engine is not reachable.'
    }
  }
}
$dockerVer = (Wsl-Bash 'docker --version 2>/dev/null; docker compose version --short 2>/dev/null').Out -split "`n"
Ok "Docker engine reachable from '$Distro' ($($dockerVer -join ' / '))"

# install.sh refuses to run without compose v2; it is part of Docker Desktop, so
# a miss here means something unusual rather than a missing package.
if (-not ((Wsl-Bash 'docker compose version > /dev/null 2>&1 && echo compose-ok').Out -match 'compose-ok')) {
  Die "the Docker Compose v2 plugin is not available in '$Distro' — update Docker Desktop."
}

# install.sh downloads the compose files with curl (or wget). Ubuntu images ship
# curl, minimal/other distros may not.
if (-not ((Wsl-Bash 'command -v curl > /dev/null 2>&1 || command -v wget > /dev/null 2>&1; echo dl-$?').Out -match 'dl-0')) {
  Info "'$Distro' has neither curl nor wget, which the installer needs to fetch the compose files."
  if ($NoInstall) { Die 'install curl in the distro: sudo apt-get install -y curl' }
  if (Confirm-Step 'Install curl in the distro now? (sudo may ask for your WSL password)' 'y') {
    Info 'apt-get update && apt-get install -y curl'
    Wsl-Interactive 'sudo apt-get update && sudo apt-get install -y curl ca-certificates'
    if ($script:WslExitCode -ne 0) {
      Die "could not install curl. Do it by hand: wsl -d $Distro -- sudo apt-get install -y curl"
    }
    Ok 'curl installed'
  } else { Die 'curl (or wget) is required inside the distro.' }
}

# ══ 4. where it lands ═════════════════════════════════════════════════════════
Step 'Install directory'

# Inside the distro's own filesystem, not /mnt/c. The stack bind-mounts a SQLite
# database, and SQLite's locking over the 9p bridge to the Windows filesystem is
# both slow and a known source of "database is locked" corruption. Explorer can
# still reach it at \\wsl$\<distro>\...
# Wsl-Bash rejects double quotes, so $HOME is read by cd'ing into it rather than
# by expanding it inside a quoted printf. A login shell may print a banner first,
# so take the last line.
$wslHome = ((Wsl-Bash 'cd && pwd').Out -split "`n")[-1]
if (-not $wslHome) { $wslHome = "/home/$WslUser" }
$defaultDir = "$wslHome/$DEFAULT_SUBDIR"

if (-not $InstallDir) {
  Info "This goes in the Linux filesystem of '$Distro', not on C:."
  foreach ($l in $STATE_NOTE) { Info $l }
  Info "From Windows you can browse it at: \\wsl`$\$Distro$($defaultDir -replace '/', '\')"
  $InstallDir = Ask 'Install directory (inside WSL)' $defaultDir
}
if ($InstallDir -match '^[A-Za-z]:[\\/]' ) {
  $conv = (Wsl-Bash ("wslpath -a " + (Sh-Quote $InstallDir))).Out
  if ($conv) { Warn "'$InstallDir' is a Windows path; using '$conv' inside WSL."; $InstallDir = $conv }
}
if ($InstallDir -match '^/mnt/[a-z]/') {
  Warn "'$InstallDir' is on the Windows filesystem."
  Warn 'Expect slow I/O and file-locking errors there. The Linux home is the safe choice.'
  if (-not $AssumeYes -and -not (Confirm-Step 'Use it anyway?' 'n')) { $InstallDir = Ask 'Install directory (inside WSL)' $defaultDir }
}
$mk = Wsl-Bash ('mkdir -p ' + (Sh-Quote $InstallDir) + ' && cd ' + (Sh-Quote $InstallDir) + ' && pwd')
if ($mk.Code -ne 0 -or -not $mk.Out) { Die "could not create '$InstallDir' inside '$Distro': $($mk.Out)" }
$InstallDir = ($mk.Out -split "`n")[-1]
Ok "installing into ${Distro}:$InstallDir"

# ══ 5. hand over to install.sh ════════════════════════════════════════════════
Step "Running the $PRODUCT installer inside WSL"

# One installer, one source of truth. Run from a clone, the checkout's own
# install.sh is used (so a local change is what runs); piped from the web, it is
# fetched inside the distro exactly as the documented Linux one-liner does.
$localSh = $null
if ($PSCommandPath) {
  $cand = Join-Path (Split-Path -Parent $PSCommandPath) $INSTALLER_SH
  if (Test-Path -LiteralPath $cand) { $localSh = $cand }
}

$shPath = "/tmp/$DEFAULT_SUBDIR-install.$PID.sh"
if ($localSh) {
  $lin = (Wsl-Bash ('wslpath -a ' + (Sh-Quote $localSh))).Out
  if (-not $lin) { Die "could not map '$localSh' into the distro." }
  Info "using $INSTALLER_SH from this checkout"
  $cp = Wsl-Bash ('cp ' + (Sh-Quote $lin) + ' ' + (Sh-Quote $shPath) + ' && chmod +x ' + (Sh-Quote $shPath))
  if ($cp.Code -ne 0) { Die "could not stage the installer: $($cp.Out)" }
} else {
  Info "fetching $InstallerUrl"
  $get = Wsl-Bash ('(command -v curl > /dev/null 2>&1 && curl -fsSL ' + (Sh-Quote $InstallerUrl) + ' -o ' + (Sh-Quote $shPath) + ') || wget -qO ' + (Sh-Quote $shPath) + ' ' + (Sh-Quote $InstallerUrl) + ' && chmod +x ' + (Sh-Quote $shPath))
  if ($get.Code -ne 0) { Die "could not download the installer: $($get.Out)" }
}

# Forward the env vars install.sh understands, so a Windows user drives it the
# same way a Linux user does — PowerShell env var in, bash env var out.
$assign = @()
foreach ($n in $FORWARD_VARS) {
  $v = [Environment]::GetEnvironmentVariable($n)
  if (-not [string]::IsNullOrWhiteSpace($v)) { $assign += ("$n=" + (Sh-Quote $v)) }
}
# These two are decided here, so they override whatever was inherited.
$assign = @($assign | Where-Object { $_ -notmatch "^($DIR_VAR|ASSUME_YES)=" })
$assign += ("$DIR_VAR=" + (Sh-Quote $InstallDir))
if ($AssumeYes) { $assign += 'ASSUME_YES=1' }
if ($assign.Count -gt 1) {
  Info ('forwarding: ' + (($assign | ForEach-Object { ($_ -split '=')[0] }) -join ' '))
}

$cmd = 'cd ' + (Sh-Quote $InstallDir) + ' && ' + ($assign -join ' ') + ' bash ' + (Sh-Quote $shPath)
Write-Host ''
Write-Host '    ----- install.sh output starts -----' -ForegroundColor DarkGray
Wsl-Interactive $cmd
$code = $script:WslExitCode
Write-Host '    ----- install.sh output ends -----' -ForegroundColor DarkGray
Wsl-Bash ('rm -f ' + (Sh-Quote $shPath)) | Out-Null
if ($code -ne 0) { Die "the $PRODUCT installer exited with $code (its output is above)." }

# ══ 6. summary ════════════════════════════════════════════════════════════════
# Deliberately short: install.sh has just printed the authoritative summary
# (URLs, the API secret, how to manage the stack). What is added here is only
# what is true on Windows and nowhere else.
Step 'Done'
Write-Host ''
Write-Host "  $PRODUCT on Windows" -ForegroundColor White
foreach ($p in $SUMMARY_PORTS) {
  # Var empty = the port is fixed in the compose file, not driven by an env var.
  $port = if ($p.Var) { EnvOr $p.Var $p.Default } else { $p.Default }
  Info ("{0,-20} http://localhost:{1}" -f $p.Label, $port)
}
Info 'Docker Desktop publishes the containers'' ports to Windows, so localhost works'
Info 'in your Windows browser with nothing else to set up.'
Write-Host ''
Write-Host '  Files & management' -ForegroundColor White
Info "Stack lives in       ${Distro}:$InstallDir"
Info "Open in Explorer     explorer.exe \\wsl`$\$Distro$($InstallDir -replace '/', '\')"
Info "Shell into it        wsl -d $Distro --cd $InstallDir"
Info "Follow the boot      wsl -d $Distro -- bash -lc 'cd $InstallDir/$STACK_SUBDIR && docker compose logs -f'"
Info "Stop it              wsl -d $Distro -- bash -lc 'cd $InstallDir/$STACK_SUBDIR && docker compose down'"
Write-Host ''
Info 'Keep Docker Desktop running (or set it to start with Windows) — the stack'
Info 'stops when the engine stops, and comes back up with it.'
Write-Host ''

} catch {
  # A Die/Quit carries its own message (or none, for a clean stop); anything else
  # is an unexpected failure and is reported as-is.
  $m = "$($_.Exception.Message)"
  if ($m.StartsWith($STOP)) {
    $text = $m.Substring($STOP.Length)
    if ($text) { Write-Host ''; Write-Host 'error: ' -ForegroundColor Red -NoNewline; Write-Host $text }
  } else {
    Write-Host ''
    Write-Host 'error: ' -ForegroundColor Red -NoNewline; Write-Host $m
    if ($_.ScriptStackTrace) { Write-Host "    $($_.ScriptStackTrace -replace "`n", "`n    ")" -ForegroundColor DarkGray }
    $script:StopCode = 1
  }
}

# A file run (or CI) gets a real exit status; a piped run only gets the variable,
# because exiting would take the user's session down with it.
$global:LASTEXITCODE = $script:StopCode
if ($PSCommandPath -and $script:StopCode -ne 0) { exit $script:StopCode }
