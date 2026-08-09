# Registers the Crew MCP server with VoiceOS on Windows, and audits the settings
# A found on the Mac (COORDINATION.md, "What A found in VoiceOS's own config").
#
#   .\register.ps1           find VoiceOS, audit its config, print the exact values to paste
#   .\register.ps1 -Apply    register it too; refuses to edit config while VoiceOS is running
#   .\register.ps1 -Apply -StopVoiceOS
#                            briefly stops VoiceOS, writes config, then launches it again
#
# SAFETY: VoiceOS's config holds live auth tokens. This script reads it but only ever
# prints a fixed allowlist of boolean/array keys. It never dumps the file. It writes
# only with -Apply, after backing up config.json. Do not paste the raw config into
# chat, the repo, or the group thread.

param([switch]$Apply, [switch]$StopVoiceOS)

$ErrorActionPreference = "Stop"
$serverPath = Join-Path $PSScriptRoot "server.js"

function Head($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Good($t) { Write-Host "  OK   $t" -ForegroundColor Green }
function Warn($t) { Write-Host "  !!   $t" -ForegroundColor Yellow }
function Bad($t)  { Write-Host "  XX   $t" -ForegroundColor Red }

function Pick($obj, [string[]]$paths) {
    foreach ($path in $paths) {
        $cur = $obj
        $found = $true
        foreach ($part in $path -split "\.") {
            if ($null -eq $cur -or $cur.PSObject.Properties.Name -notcontains $part) {
                $found = $false
                break
            }
            $cur = $cur.$part
        }
        if ($found) { return [pscustomobject]@{ Found = $true; Path = $path; Value = $cur } }
    }
    return [pscustomobject]@{ Found = $false; Path = $null; Value = $null }
}

function MatchingKeys($obj, [string]$prefix = "") {
    if ($null -eq $obj -or $obj -isnot [pscustomobject]) { return @() }
    $matches = @()
    foreach ($prop in $obj.PSObject.Properties) {
        $path = if ($prefix) { "$prefix.$($prop.Name)" } else { $prop.Name }
        if ($prop.Name -match "confirm|trust|autoApprove|auto_approve|requireApproval") {
            $matches += $path
        }
        if ($prop.Value -is [pscustomobject]) {
            $matches += MatchingKeys $prop.Value $path
        }
    }
    return $matches
}

function VoiceOSProcesses() {
    @(Get-Process -Name VoiceOS -ErrorAction SilentlyContinue)
}

# C hit this on macOS and it cost an hour: registering the bare word "node" means
# VoiceOS has to find node on ITS PATH, and a GUI app launched from Explorer or the
# Start menu never sources a shell profile. When it can't, the error is
# "MCP error -32000: Connection closed" -- which reads as a broken server rather
# than a missing interpreter, so you debug the wrong thing.
#
# Windows is usually luckier than macOS here: a machine-wide Node install lands in
# "C:\Program Files\nodejs" and goes on the SYSTEM PATH, which GUI apps do inherit,
# and nvm-windows keeps that same path as a symlink to the active version -- so it
# stays correct across "nvm use". fnm and Volta install per-user and lean on shell
# hooks, and those are exactly the setups a GUI app cannot see.
#
# Order: the GUI-visible machine path if it is really there, else the resolved
# absolute path, saying why. Never the bare word.
function Resolve-NodeCommand() {
    $resolved = $null
    $cmd = Get-Command node -ErrorAction SilentlyContinue
    if ($cmd) { $resolved = $cmd.Source }

    $machine = Join-Path $env:ProgramFiles "nodejs\node.exe"
    if (Test-Path $machine) {
        return [pscustomobject]@{
            Path = $machine
            Why  = "machine-wide install on the system PATH -- visible to VoiceOS launched from Explorer"
            Warn = $null
        }
    }
    if ($resolved) {
        return [pscustomobject]@{
            Path = $resolved
            Why  = "resolved from this shell's PATH"
            Warn = "node is NOT in `"$machine`" -- this looks like fnm/Volta/a per-user install. " +
                   "Registering the absolute path so VoiceOS can start it without a shell, but it is " +
                   "version-pinned: re-run this script after switching node versions."
        }
    }
    return [pscustomobject]@{
        Path = $null
        Why  = $null
        Warn = "No node on PATH at all. Install Node before registering."
    }
}

function SetProp($obj, [string]$name, $value) {
    $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
}

function WriteJsonNoBom($path, $value) {
    $json = $value | ConvertTo-Json -Depth 100
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $json, $utf8NoBom)
}

function Write-CrewMcpConfig($configPath, $serverPath, $nodePath) {
    $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
    $servers = @()
    if ($null -ne $cfg.customMcpServers) { $servers = @($cfg.customMcpServers) }

    $existing = $servers | Where-Object { $_.name -eq "crew" } | Select-Object -First 1
    if ($existing) {
        SetProp $existing "transport" "stdio"
        SetProp $existing "command" $nodePath
        SetProp $existing "args" @($serverPath)
        SetProp $existing "enabled" $true
        SetProp $existing "url" $null
        SetProp $existing "headers" $null
        SetProp $existing "env" $null
        return @{ Config = $cfg; Servers = $servers; Action = "updated"; Id = $existing.id }
    }

    $id = [guid]::NewGuid().ToString()
    $servers += [pscustomobject]@{
        id = $id
        name = "crew"
        transport = "stdio"
        command = $nodePath
        args = @($serverPath)
        enabled = $true
    }
    SetProp $cfg "customMcpServers" $servers
    return @{ Config = $cfg; Servers = $servers; Action = "added"; Id = $id }
}

# ---------------------------------------------------------------- find VoiceOS
Head "Locating VoiceOS"

$cli = Get-Command voiceos -ErrorAction SilentlyContinue
if ($cli) { Good "CLI on PATH: $($cli.Source)" } else { Bad "No 'voiceos' on PATH." }

# Electron apps put per-user config in %APPDATA%\<AppName>. A found the Mac copy at
# ~/Library/Application Support/VoiceOS/config.json; this is the Windows analogue.
$candidates = @(
    (Join-Path $env:APPDATA        "VoiceOS"),
    (Join-Path $env:LOCALAPPDATA   "VoiceOS"),
    (Join-Path $env:LOCALAPPDATA   "Programs\VoiceOS"),
    (Join-Path $env:ProgramFiles   "VoiceOS")
) | Where-Object { Test-Path $_ }

if ($candidates) { $candidates | ForEach-Object { Good "Found directory: $_" } }
else { Bad "No VoiceOS directory in AppData or Program Files." }

if (-not $cli -and -not $candidates) {
    Write-Host @"

VoiceOS is not installed on this machine.

  1. Download the Windows build from https://www.voiceos.com/  ("Download for Windows")
  2. Install it, sign in, and redeem the event's free-month code
  3. Finish onboarding -- A found the Mac copy stuck at step 15 with
     onboardingCompleted:false, which may gate Agent Mode
  4. Re-run this script

Nothing else in voiceos-bridge/ is blocked on this. The MCP server is built and tested
against the real orchestrator; this only registers it and checks the settings.
"@ -ForegroundColor DarkGray
    exit 1
}

# ------------------------------------------------------------------ audit config
$configPath = $candidates | ForEach-Object { Join-Path $_ "config.json" } |
              Where-Object { Test-Path $_ } | Select-Object -First 1

$crewRegistered = $false
$crewBareCommand = $false

if ($configPath) {
    Head "Config audit  ($configPath)"
    Write-Host "  (reading an allowlist of keys only -- this file holds live auth tokens)" -ForegroundColor DarkGray
    $cfg = Get-Content $configPath -Raw | ConvertFrom-Json

    # Each of these silently broke, or nearly broke, the loop on the Mac. VoiceOS
    # has shipped both top-level and nested config shapes, so accept either and
    # print the path we actually found.
    $mute = Pick $cfg @("settings.muteWhenDictating", "muteWhenDictating")
    if ($mute.Found) {
        if ($mute.Value) {
            Warn "$($mute.Path) = true -- VoiceOS ducks system audio while listening."
            Warn "     On a loopback rig that mutes the very thing it is supposed to hear."
            Warn "     Set false before any voice-loop test. (Windows-only demo? harmless.)"
        } else { Good "$($mute.Path) = false" }
    }
    $agentVoice = Pick $cfg @("settings.agentVoiceEnabled", "agentVoiceEnabled")
    if ($agentVoice.Found) {
        if ($agentVoice.Value) {
            Warn "$($agentVoice.Path) = true -- VoiceOS talks back, and in a loopback rig it"
            Warn "     hears its own replies and re-triggers itself. Turn off for the demo."
        } else { Good "$($agentVoice.Path) = false" }
    }
    $integrations = Pick $cfg @("connectedIntegrations", "settings.connectedIntegrations")
    if ($integrations.Found) {
        $ints = @($integrations.Value)
        Write-Host "  --   connectedIntegrations: $($ints -join ', ')"
        if ($ints -notcontains "gmail" -and $ints -notcontains "googlemail") {
            Warn "     No Gmail. Same as A's Mac -- the inbox half has no native VoiceOS path."
        }
    }
    $toggles = Pick $cfg @("nativeActionToggles", "settings.nativeActionToggles")
    if ($toggles.Found) {
        $acts = $toggles.Value.PSObject.Properties.Name
        Write-Host "  --   nativeActionToggles: $($acts -join ', ')"
    }
    $onboarding = Pick $cfg @("onboarding.onboardingCompleted", "onboardingCompleted")
    if ($onboarding.Found) {
        if ($onboarding.Value) { Good "$($onboarding.Path) = true" }
        else { Warn "$($onboarding.Path) = false -- may gate Agent Mode. Finish onboarding." }
    }
    # The open question from COORDINATION.md: is there a trust / auto-confirm switch?
    $trustKeys = MatchingKeys $cfg | Select-Object -Unique
    if ($trustKeys) { Warn "Possible confirmation/trust keys, INSPECT THESE: $($trustKeys -join ', ')" }
    else { Good "No confirm/trust key in config -- matches A's Mac finding (no bypass switch)." }

    $servers = Pick $cfg @("customMcpServers", "settings.customMcpServers")
    $existing = if ($servers.Found -and $null -ne $servers.Value) { @($servers.Value) } else { @() }
    $serverCount = @($existing | Where-Object { $null -ne $_ }).Count
    Write-Host "  --   customMcpServers currently: $(if ($serverCount -gt 0) { $serverCount } else { 'empty' })"
    $crew = @($existing | Where-Object { $_.name -eq "crew" } | Select-Object -First 1)
    if ($crew.Count -gt 0 -and $crew[0].enabled -ne $false) {
        $crewRegistered = $true
        Good "crew MCP server is registered and enabled"
    } elseif ($crew.Count -gt 0) {
        Warn "crew MCP server exists but is disabled"
    }
    # An entry registered as the bare word "node" works only while VoiceOS happens to
    # inherit a PATH containing it. That is true of a machine-wide install and false
    # of fnm/Volta -- and when it is false the error names the connection, not node.
    if ($crew.Count -gt 0) {
        $registeredCmd = $crew[0].command
        Write-Host "  --   crew command: $registeredCmd"
        if ($registeredCmd -and $registeredCmd -notmatch "[\\/]") {
            $crewBareCommand = $true
            Warn "     registered as a bare command, not a path. Works only if VoiceOS's own"
            Warn "     PATH has it. Re-run with -Apply -StopVoiceOS to pin the absolute path."
        }
    }
} else {
    Warn "No config.json found yet -- VoiceOS may need to be launched once first."
}

# ---------------------------------------------------------------- registration
Head "Register the Crew MCP server"

if (-not (Test-Path $serverPath)) { Bad "server.js not found at $serverPath"; exit 1 }

$node = Resolve-NodeCommand
if (-not $node.Path) { Bad $node.Warn; exit 1 }
if ($node.Warn) { Warn $node.Warn } else { Good "node: $($node.Why)" }

Write-Host "  command : `"$($node.Path)`""
Write-Host "  args    : `"$serverPath`""
Write-Host "  (both absolute on purpose -- VoiceOS gets no shell, no cwd and no PATH of ours)"

Write-Host "`n  Sanity check before registering..." -ForegroundColor DarkGray
# node writes the selftest result to stderr on purpose (stdout is the MCP channel).
# PowerShell wraps native stderr in NativeCommandError, and $ErrorActionPreference=Stop
# then makes it fatal -- so merge the streams down in cmd, where PowerShell can't see them.
$selftest = cmd /c "node `"$serverPath`" --selftest 2>&1"
($selftest | Select-String "PASS|FAIL") | ForEach-Object { Write-Host "  $($_.ToString().Trim())" }

if ($cli) {
    if ($Apply) {
        Head "Running: voiceos add mcp"
        & voiceos add mcp
    } else {
        Write-Host "`n  Run it:  voiceos add mcp        (or re-run this script with -Apply)" -ForegroundColor Cyan
    }
} else {
    if ($Apply) {
        Head "Writing registration (there is no CLI on Windows)"
        if (-not $configPath) {
            Bad "Cannot apply without config.json. Launch VoiceOS once, finish onboarding, then re-run."
            exit 1
        }

        $running = VoiceOSProcesses
        $restartExe = $running | Select-Object -First 1 -ExpandProperty Path
        if ($running.Count -gt 0 -and -not $StopVoiceOS) {
            Warn "VoiceOS is running ($($running.Count) process(es)); refusing to hand-edit config.json underneath it."
            Write-Host "  Re-run with:  .\register.ps1 -Apply -StopVoiceOS" -ForegroundColor Cyan
            Write-Host "  That briefly stops VoiceOS, writes customMcpServers, and launches it again." -ForegroundColor DarkGray
            exit 2
        }

        if ($running.Count -gt 0 -and $StopVoiceOS) {
            Warn "Stopping VoiceOS so the electron-store config edit will stick..."
            foreach ($p in $running) {
                try { $p.CloseMainWindow() | Out-Null } catch {}
            }
            Start-Sleep -Seconds 2
            $still = VoiceOSProcesses
            if ($still.Count -gt 0) { $still | Stop-Process -Force }
            Start-Sleep -Milliseconds 500
        }

        $before = Get-Content $configPath -Raw
        $backup = "$configPath.crew-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($backup, $before, $utf8NoBom)
        $update = Write-CrewMcpConfig $configPath $serverPath $node.Path
        WriteJsonNoBom $configPath $update.Config
        Good "Crew MCP server $($update.Action) in customMcpServers (id $($update.Id))."
        Good "Backup written: $backup"

        if ($restartExe) {
            Start-Process $restartExe
            Good "VoiceOS launched again. Open Settings -> MCP / custom servers and refresh if needed."
        }
    } else {
        if ($crewRegistered) {
            Head "Registration status"
            Good "VoiceOS already has an enabled custom MCP server named crew."
            if ($crewBareCommand) {
                Warn "But its command is the bare word, not the path printed above."
                Write-Host "  Pin it before the demo:  .\register.ps1 -Apply -StopVoiceOS" -ForegroundColor Cyan
            } else {
                Write-Host "  Re-run with .\register.ps1 -Apply -StopVoiceOS only if the path changes." -ForegroundColor DarkGray
            }
        } else {
            Head "How to actually register (there is no CLI on Windows)"
    Write-Host @"
  VoiceOS for Windows ships ONE executable and no command-line interface --
  'voiceos add mcp' does not exist here. Registration is in-app:

      tray icon -> VoiceOS window -> Settings -> MCP / custom servers -> Add

  and it writes into `customMcpServers` in
      $env:APPDATA\VoiceOS\config.json

  Do NOT hand-edit that file while VoiceOS is running -- it is an electron-store
  and the app rewrites the whole file on its own schedule, so your entry vanishes.
  Quit VoiceOS first if you edit it at all.

  To let this script do the safe edit for you:

      .\register.ps1 -Apply -StopVoiceOS

  It backs up config.json, writes the crew MCP entry, then launches VoiceOS again.
"@ -ForegroundColor DarkGray
        }
    }
}

Head "Then prove the outer loop"
Write-Host @"
  1. tail the audit log:
       Get-Content voiceos-bridge\mcp-server\crew-bridge.log -Wait
  2. start the orchestrator (canned agents, no Claude spend):
       `$env:FAKE=1; node orchestrator\server.js
  3. say into the mic:  "clean up my inbox and schedule everything"
  4. a run_crew_task line should appear in the log with your transcript in it.

  The log is written BEFORE the orchestrator is called, so even if :4001 is down you
  still get proof of exactly what VoiceOS heard.
"@ -ForegroundColor DarkGray
