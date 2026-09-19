# alarm-stop.ps1 — Windows port of alarm-stop.sh: silence every running alarm
# started by alarm-start.ps1.
#
# Registered as a UserPromptSubmit hook, so it runs on EVERY prompt the user
# submits, in every session. Two consequences, both deliberate:
#   * it prints nothing on the normal path (hook output is injected into
#     Claude's context, and chatter here would pollute every single prompt)
#   * it always exits 0, and returns at once when no alarm exists
#
# It also restores the system output volume that alarm-start.ps1 raised. On
# Windows this is the main restore, not a backstop: the alarm is killed
# outright, so its own cleanup never runs.
#
# UNTESTED — written without a Windows machine; see "Windows" in SKILL.md.
# Takes no arguments. Safe to run when no alarm exists.

$State = Join-Path $env:USERPROFILE '.claude\.get-back-alarm'
if (-not (Test-Path $State)) { exit 0 }

foreach ($f in Get-ChildItem -Path $State -Filter '*.pid' -ErrorAction SilentlyContinue) {
    $id = $f.BaseName
    if ($id -match '^\d+$') {
        # Only kill a PowerShell process: a stale file may name a process id
        # that Windows has since given to something else.
        $p = Get-Process -Id ([int]$id) -ErrorAction SilentlyContinue
        if ($p -and $p.ProcessName -eq 'powershell') {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            Wait-Process -Id $p.Id -Timeout 2 -ErrorAction SilentlyContinue
        }
    }
    Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
}

# Volume last, so a still-dying alarm cannot raise it again after we put it
# back. The file holds "<level> <muted>" as they were before the alarm began.
foreach ($f in Get-ChildItem -Path $State -Filter '*.vol' -ErrorAction SilentlyContinue) {
    $vol, $muted = (Get-Content $f.FullName -ErrorAction SilentlyContinue | Select-Object -First 1) -split ' '
    if ($vol -match '^\d+$') {
        try {
            . (Join-Path $PSScriptRoot 'win-audio.ps1')
            [GbAudio]::SetVolume([int]$vol)
            if ($muted -eq 'true') { [GbAudio]::SetMute($true) }
        } catch { }
    }
    Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
}

exit 0
