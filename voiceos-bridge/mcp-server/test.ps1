# One-command go/no-go for the VoiceOS bridge.  .\test.ps1
# Starts a stub orchestrator, drives server.js over real stdio pipes, prints PASS/FAIL.
# Use -Real to test against A's orchestrator instead of the stub (start it yourself first).
param([switch]$Real, [string]$Phrase = "clean up my inbox and schedule everything")

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$stub = $null

if (-not $Real) {
    $listening = @(Get-NetTCPConnection -LocalPort 4001 -State Listen -ErrorAction SilentlyContinue)
    if ($listening.Count -gt 0) {
        Write-Host "  :4001 already in use - testing against whatever is there." -ForegroundColor Yellow
    } else {
        $stub = Start-Process node -ArgumentList "$here\stub-orchestrator.js" -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput "$here\stub.out" -RedirectStandardError "$here\stub.err"
        Start-Sleep -Milliseconds 900
        Write-Host "  stub orchestrator up on :4001 (pid $($stub.Id))" -ForegroundColor DarkGray
    }
}

try {
    $env:PHRASE = $Phrase
    # The stub's run is scripted, so the follow-up loop must actually reach
    # "the crew is finished". A real orchestrator paces at LINE_MS and won't.
    $env:REQUIRE_DONE = if ($Real) { "0" } else { "1" }
    & node "$here\test-stdio.js"
    $code = $LASTEXITCODE

    if ($code -eq 0 -and -not $Real -and (Test-Path "$here\stub.out")) {
        Write-Host "`n--- what the orchestrator actually received ---" -ForegroundColor Cyan
        Get-Content "$here\stub.out" | Select-Object -Last 14
    }
} finally {
    if ($stub -and -not $stub.HasExited) {
        Stop-Process -Id $stub.Id -Force
        Write-Host "`n  stub stopped." -ForegroundColor DarkGray
    }
}

exit $code
