# The show, on Windows.  .\run-demo.ps1
#
# run-demo.sh builds and launches the Swift dock, so it is macOS-only and always
# will be. Four of us are on Macs and one of us is not, which meant B could never
# run the thing B was building against. This is the same pipeline minus the only
# macOS-shaped part: characters and speech are replaced by fake-dock printing what
# it received, in order, as it arrives.
#
#   .\run-demo.ps1            canned agents, whole pipeline, zero Claude spend
#   .\run-demo.ps1 -Real      real headless agents (needs a logged-in `claude`)
#   .\run-demo.ps1 -Talk      the demo as a conversation -- this is the pitch
#   .\run-demo.ps1 -Voice     orchestrator up, then YOU SPEAK into VoiceOS
#   .\run-demo.ps1 -Stop      kill everything
#
# -Voice is the real one: VoiceOS hears you, calls run_crew_task on the MCP
# server, and the crew runs. It needs the crew server registered in VoiceOS
# (Settings -> MCP) -- .\voiceos-bridge\mcp-server\register.ps1 prints the exact
# command and args, and tells you if it is not registered yet.

param(
    [switch]$Real,
    [switch]$Talk,
    [switch]$Voice,
    [switch]$Stop,
    [string]$Phrase = "clean up my inbox and schedule everything"
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$log = Join-Path $env:TEMP "crew-dock.log"
$orchLog = Join-Path $env:TEMP "crew-orch.log"

function Say($t, $c = "Gray") { Write-Host $t -ForegroundColor $c }

# Free both ports first. A leftover orchestrator owns :4001 and then everything
# quietly reports on THAT one instead -- A's EADDRINUSE guard catches it, but only
# if we are not the ones who left it running.
function Stop-Crew {
    foreach ($p in 4001, 4002) {
        Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue |
            ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
    }
    Start-Sleep -Milliseconds 400
}

if ($Stop) { Stop-Crew; Say "stopped." Green; exit 0 }

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Say "node is not on PATH -- the orchestrator and the MCP server both need it." Red; exit 1
}

Stop-Crew

# --- the dock stand-in -------------------------------------------------------
# Not the real dock: no characters, no speech. It prints what it was sent, which
# is the part this machine can honestly show.
$dock = Start-Process node -ArgumentList "$root\orchestrator\fake-dock.js" -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $log -RedirectStandardError "$log.err"
Start-Sleep -Milliseconds 700
if ($dock.HasExited) { Say "fake dock failed to start -- see $log.err" Red; exit 1 }
Say "dock stand-in on :4002  (log: $log)" DarkGray

# --- the orchestrator --------------------------------------------------------
$env:FAKE = if ($Real -or $Voice) { $null } else { "1" }
if ($Voice) { $env:CREW_MODE = "narrate" }   # never point a spoken run at real mail by accident
$mode = if ($Real -or $Voice) { "real agents" } else { "canned agents, no Claude spend" }

$orch = Start-Process node -ArgumentList "$root\orchestrator\server.js" -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $orchLog -RedirectStandardError "$orchLog.err"
Start-Sleep -Milliseconds 900
if ($orch.HasExited) {
    Say "orchestrator failed to start:" Red
    Get-Content "$orchLog.err", $orchLog -ErrorAction SilentlyContinue | Select-Object -Last 6 | ForEach-Object { "  $_" }
    Stop-Crew; exit 1
}
Say "orchestrator on :4001  ($mode)" DarkGray

try {
    # --- the conversation: the product, not the machinery --------------------
    if ($Talk) {
        Say "`n  the demo as a conversation -- this is what VoiceOS will drive`n" Cyan
        & node "$root\voiceos-bridge\mcp-server\demo-conversation.js"
        exit $LASTEXITCODE
    }

    # --- voice: you speak, and we show what actually arrived -----------------
    if ($Voice) {
        $cfg = Join-Path $env:APPDATA "VoiceOS\config.json"
        if (Test-Path $cfg) {
            $n = @((Get-Content $cfg -Raw | ConvertFrom-Json).customMcpServers).Count
            if ($n -eq 0) {
                Say "`n  VoiceOS has NO custom MCP server registered, so it cannot reach the crew." Yellow
                Say "  Register it first (in-app, there is no CLI on Windows):" Yellow
                Say "    .\voiceos-bridge\mcp-server\register.ps1     <- prints the exact command + args`n" Yellow
            } else {
                Say "  VoiceOS has $n custom MCP server(s) registered." Green
            }
        }
        Say "`n  SPEAK NOW:  `"$Phrase`"" Cyan
        Say "  (hands-free, or your VoiceOS trigger chord)`n" DarkGray
        Say "  waiting for a run_crew_task to land... Ctrl-C to give up.`n" DarkGray

        $bridge = Join-Path $root "voiceos-bridge\mcp-server\crew-bridge.log"
        $before = if (Test-Path $bridge) { (Get-Content $bridge).Count } else { 0 }
        $deadline = (Get-Date).AddMinutes(3)
        $heard = $null
        while ((Get-Date) -lt $deadline -and -not $heard) {
            Start-Sleep -Milliseconds 700
            if (-not (Test-Path $bridge)) { continue }
            $new = Get-Content $bridge | Select-Object -Skip $before
            foreach ($line in $new) {
                try { $rec = $line | ConvertFrom-Json } catch { continue }
                if ($rec.event -eq 'run_crew_task') { $heard = $rec.instructions; break }
            }
        }
        if (-not $heard) {
            Say "  Nothing arrived in 3 minutes." Red
            Say "  The audit log is written BEFORE the orchestrator is called, so an empty" DarkGray
            Say "  log means VoiceOS never called us -- registration or transcription, not us." DarkGray
            Stop-Crew; exit 1
        }
        Say "  VoiceOS heard:  `"$heard`"" Green
        Say "  ...which is what reached the crew, verbatim.`n" DarkGray
    }
    else {
        # --- typed trigger, same entry point VoiceOS uses --------------------
        Say "`n  trigger:  `"$Phrase`"" Cyan
        $body = @{ instructions = $Phrase } | ConvertTo-Json -Compress
        $res = Invoke-RestMethod -Uri "http://localhost:4001/start-task" -Method Post `
            -ContentType "application/json" -Body $body
        Say "  task $($res.taskId) started`n" DarkGray
    }

    # --- watch it happen -----------------------------------------------------
    Say "  what the dock actually received:`n" Cyan
    $seen = 0
    $deadline = (Get-Date).AddMinutes(4)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        $lines = @(Get-Content $log -ErrorAction SilentlyContinue)
        for ($i = $seen; $i -lt $lines.Count; $i++) {
            $m = [regex]::Match($lines[$i], '^DOCK <- (.*)$')
            if (-not $m.Success) { continue }
            try { $p = $m.Groups[1].Value | ConvertFrom-Json } catch { continue }
            # The final "Done:" line is posted twice -- once working, then done.
            # Show the state so the second one reads as the sign-off, not a repeat.
            $tag = "{0,-10}" -f $p.character
            $col = if ($p.state -eq 'done') { 'Green' } else { 'White' }
            Say ("    {0} {1}" -f $tag, $p.message) $col
        }
        $seen = $lines.Count
        $status = try { Invoke-RestMethod -Uri "http://localhost:4001/status/task_1" -TimeoutSec 3 } catch { $null }
        if ($status -and $status.status -eq 'done') { Start-Sleep -Milliseconds 900; break }
    }

    # Truth from the dock's own log, not from what we think we sent. The
    # orchestrator log reports what it SENT; only this says what arrived.
    $recv = @(Select-String -Path $log -Pattern '^DOCK <- ' -ErrorAction SilentlyContinue).Count
    Say ""
    if ($recv -eq 0) {
        Say "  NOTHING reached the dock. The orchestrator log will still look perfect." Red
        Say "  That is the trap: it reports what it sent. Check $orchLog" DarkGray
    } else {
        Say "  $recv lines reached the dock." Green
        Say "  On a Mac these are three characters walking out and saying it out loud." DarkGray
    }
}
finally {
    Stop-Crew
    Say "`nstopped. (.\run-demo.ps1 -Stop if anything survives)" DarkGray
}
