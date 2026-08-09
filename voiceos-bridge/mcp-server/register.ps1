# Registers the Crew MCP server with VoiceOS on Windows, and audits the settings
# A found on the Mac (COORDINATION.md, "What A found in VoiceOS's own config").
#
#   .\register.ps1           find VoiceOS, audit its config, print the exact register command
#   .\register.ps1 -Apply    also run `voiceos add mcp`
#
# SAFETY: VoiceOS's config holds live auth tokens. This script reads it but only ever
# prints a fixed allowlist of boolean/array keys. It never dumps the file, and it never
# writes it. Do not paste the raw config into chat, the repo, or the group thread.

param([switch]$Apply)

$ErrorActionPreference = "Stop"
$serverPath = Join-Path $PSScriptRoot "server.js"

function Head($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Good($t) { Write-Host "  OK   $t" -ForegroundColor Green }
function Warn($t) { Write-Host "  !!   $t" -ForegroundColor Yellow }
function Bad($t)  { Write-Host "  XX   $t" -ForegroundColor Red }

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

if ($configPath) {
    Head "Config audit  ($configPath)"
    Write-Host "  (reading an allowlist of keys only -- this file holds live auth tokens)" -ForegroundColor DarkGray
    $cfg = Get-Content $configPath -Raw | ConvertFrom-Json

    # Each of these silently broke, or nearly broke, the loop on the Mac.
    if ($null -ne $cfg.muteWhenDictating) {
        if ($cfg.muteWhenDictating) {
            Warn "muteWhenDictating = true -- VoiceOS ducks system audio while listening."
            Warn "     On a loopback rig that mutes the very thing it is supposed to hear."
            Warn "     Set false before any voice-loop test. (Windows-only demo? harmless.)"
        } else { Good "muteWhenDictating = false" }
    }
    if ($null -ne $cfg.agentVoiceEnabled) {
        if ($cfg.agentVoiceEnabled) {
            Warn "agentVoiceEnabled = true -- VoiceOS talks back, and in a loopback rig it"
            Warn "     hears its own replies and re-triggers itself. Turn off for the demo."
        } else { Good "agentVoiceEnabled = false" }
    }
    if ($null -ne $cfg.connectedIntegrations) {
        $ints = @($cfg.connectedIntegrations)
        Write-Host "  --   connectedIntegrations: $($ints -join ', ')"
        if ($ints -notcontains "gmail" -and $ints -notcontains "googlemail") {
            Warn "     No Gmail. Same as A's Mac -- the inbox half has no native VoiceOS path."
        }
    }
    if ($null -ne $cfg.nativeActionToggles) {
        $acts = $cfg.nativeActionToggles.PSObject.Properties.Name
        Write-Host "  --   nativeActionToggles: $($acts -join ', ')"
    }
    if ($null -ne $cfg.onboardingCompleted) {
        if ($cfg.onboardingCompleted) { Good "onboardingCompleted = true" }
        else { Warn "onboardingCompleted = false -- may gate Agent Mode. Finish onboarding." }
    }
    # The open question from COORDINATION.md: is there a trust / auto-confirm switch?
    $trustKeys = $cfg.PSObject.Properties.Name | Where-Object {
        $_ -match "confirm|trust|autoApprove|auto_approve|requireApproval"
    }
    if ($trustKeys) { Warn "Possible confirmation/trust keys, INSPECT THESE: $($trustKeys -join ', ')" }
    else { Good "No confirm/trust key in config -- matches A's Mac finding (no bypass switch)." }

    $existing = @($cfg.customMcpServers)
    Write-Host "  --   customMcpServers currently: $(if ($existing.Count) { $existing.Count } else { 'empty' })"
} else {
    Warn "No config.json found yet -- VoiceOS may need to be launched once first."
}

# ---------------------------------------------------------------- registration
Head "Register the Crew MCP server"

if (-not (Test-Path $serverPath)) { Bad "server.js not found at $serverPath"; exit 1 }
Write-Host "  command : node"
Write-Host "  args    : `"$serverPath`""
Write-Host "  (absolute path on purpose -- VoiceOS's working directory is not this folder)"

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

  BLOCKED TODAY: the app opens onto a paywall ("Start your 7-day free trial",
  `$143.88/yr after). Onboarding terminates there with no skip, and
  onboardingCompleted stays false. Redeem the event's free month on the account
  first -- do not start the paid trial by accident.
"@ -ForegroundColor DarkGray
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
