# Every B-side check, one command.  .\voiceos-bridge\verify.ps1
#
# Run this before rehearsal and after pulling anyone's changes. It starts what it
# needs, tests, and cleans up after itself. Nothing here touches a real account.
#
#   -Real    test against A's orchestrator instead of the stub (start it yourself)
#   -Google  also run the demo flow against the real Google account (needs token.json)

param([switch]$Real, [switch]$Google)

$root = Split-Path $PSScriptRoot -Parent
$mcp = Join-Path $PSScriptRoot "mcp-server"
$seed = Join-Path $PSScriptRoot "demo-seed"
$results = [ordered]@{}
$started = $null

function Section($n) { Write-Host "`n$('=' * 64)`n  $n`n$('=' * 64)" -ForegroundColor Cyan }

# node writes these suites' output to stderr/stdout mixed; merge in cmd so
# PowerShell's NativeCommandError doesn't turn a passing test into a failure.
function Run($label, $cmdline, $workdir) {
    Section $label
    Push-Location $workdir
    try {
        $out = cmd /c "$cmdline 2>&1"
        $code = $LASTEXITCODE
        $out | ForEach-Object { Write-Host "  $_" }
        $results[$label] = $code
        return $code
    } finally { Pop-Location }
}

if (-not $Real) {
    $busy = @(Get-NetTCPConnection -LocalPort 4001 -State Listen -ErrorAction SilentlyContinue)
    if ($busy.Count -eq 0) {
        $started = Start-Process node -ArgumentList "$mcp\stub-orchestrator.js" -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput "$mcp\stub.out" -RedirectStandardError "$mcp\stub.err"
        Start-Sleep -Milliseconds 900
        Write-Host "stub orchestrator up on :4001 (pid $($started.Id))" -ForegroundColor DarkGray
    } else {
        Write-Host ":4001 already in use - testing against whatever is listening." -ForegroundColor Yellow
    }
}

try {
    Run "1. MCP protocol (in-process)"    "node server.js --selftest"      $mcp | Out-Null
    Run "2. What the crew says out loud"  "node test-status-speech.js"     $mcp | Out-Null
    # Against the stub the whole run is scripted, so the status loop MUST reach
    # "the crew is finished". Against a real orchestrator it paces at LINE_MS and
    # won't inside one test, so only the stub run demands it.
    $stdio = if ($Real) { "node test-stdio.js" } else { "set REQUIRE_DONE=1 && node test-stdio.js" }
    Run "3. MCP transport + status loop"  $stdio                           $mcp | Out-Null
    Run "4. Demo flow vs mailbox"         "node test-demo-flow.js"         $mcp | Out-Null
    Run "5. demo-seed fixtures"           "uv run seed.py --dry-run"       $seed | Out-Null
    if ($Google) {
        Run "6. Demo flow vs REAL Google" "set CREW_BACKEND=google && node test-demo-flow.js" $mcp | Out-Null
    }
} finally {
    if ($started -and -not $started.HasExited) {
        Stop-Process -Id $started.Id -Force
        Write-Host "`nstub stopped." -ForegroundColor DarkGray
    }
}

Section "Summary"
$failed = 0
foreach ($k in $results.Keys) {
    $code = $results[$k]
    # test-stdio.js uses exit 2 for "transport fine, nothing on :4001" - not a failure
    # of our code, so call it out rather than burying it in a red PASS/FAIL count.
    if ($code -eq 0)      { Write-Host ("  PASS  " + $k) -ForegroundColor Green }
    elseif ($code -eq 2)  { Write-Host ("  WARN  " + $k + "  (orchestrator not running)") -ForegroundColor Yellow }
    else                  { Write-Host ("  FAIL  " + $k + "  (exit $code)") -ForegroundColor Red; $failed++ }
}

if ($failed) {
    Write-Host "`n$failed suite(s) failed.`n" -ForegroundColor Red
    exit 1
}
Write-Host "`nAll green. B's side is demo-ready." -ForegroundColor Green
Write-Host "Still gated on someone else: VoiceOS Pro trial, and a demo Google account for the 'google' backend.`n" -ForegroundColor DarkGray
exit 0
