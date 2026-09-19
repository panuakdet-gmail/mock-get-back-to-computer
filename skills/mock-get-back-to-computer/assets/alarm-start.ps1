# alarm-start.ps1 — Windows port of alarm-start.sh: start a detached,
# escalating audible alarm that keeps sounding until alarm-stop.ps1 kills it
# (or the safety cap expires).
#
# Usage: powershell.exe -NoProfile -ExecutionPolicy Bypass -File alarm-start.ps1 "<spoken message>" [max_minutes]
#   max_minutes  positive integer   stop after this long   (default 60)
#                0 | never | none   never stop on its own
#                anything else      treated as 60
#
# Returns immediately, printing the process id of the running alarm.
#
# UNTESTED — written without a Windows machine, as a courtesy. The agent running
# it owns making it work; see "Windows" in SKILL.md.
#
# Like the Mac version it manages the system output volume: it unmutes, raises
# the level to a floor, escalates that floor as the wait drags on, and puts
# everything back when it stops. It never turns the user down, and it backs off
# the moment they touch the volume themselves. It also shows one Windows
# notification, so there is something to see even if no sound comes out.

param(
    [Parameter(Position = 0)] [string]$Message = 'get back to the computer',
    [Parameter(Position = 1)] [string]$MaxMinutes = '60',
    [switch]$Run,
    [string]$MessageB64
)

$State = Join-Path $env:USERPROFILE '.claude\.get-back-alarm'
$Media = Join-Path $env:WINDIR 'Media'

$VolCeiling = 85        # never louder than this — the top of the scale distorts
                        # cheap speakers and makes the speech LESS intelligible

# ---------------------------------------------------------------- launcher --
# Called without -Run: spawn the loop as a hidden, separate process and return.
# Everything the alarm plays runs inside that one process, so killing it
# silences everything at once.
if (-not $Run) {
    if (-not $Message) { $Message = 'get back to the computer' }
    if ($MaxMinutes -notmatch '^(\d+|never|none|off)$') { $MaxMinutes = '60' }

    New-Item -ItemType Directory -Force -Path $State -ErrorAction Stop | Out-Null

    # The message travels as base64 so quotes and spaces survive the command line.
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Message))

    # Always Windows PowerShell 5.1, even when launched from PowerShell 7:
    # System.Speech is missing from PowerShell 7.
    $exe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $p = Start-Process -FilePath $exe -WindowStyle Hidden -PassThru -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"",
        '-Run', '-MessageB64', $b64, '-MaxMinutes', $MaxMinutes)

    Set-Content -Path (Join-Path $State "$($p.Id).pid") -Value $p.Id
    Write-Output $p.Id
    exit 0
}

# --------------------------------------------------------------- the alarm --
$msg = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($MessageB64)).TrimEnd('.')
$cap = $MaxMinutes
$pidFile = Join-Path $State "$PID.pid"
$volFile = Join-Path $State "$PID.vol"

# ------------------------------------------------------------ output volume --
# If the volume code cannot load or read a level, leave volume alone and play
# at whatever is set.
$manageVolume = $false
try {
    . (Join-Path $PSScriptRoot 'win-audio.ps1')
    $origVol  = [GbAudio]::GetVolume()
    $origMute = [GbAudio]::GetMute()
    $manageVolume = $true
} catch { }

$userMuted = $false
$lastSet = $null
$ceiling = $VolCeiling

function Restore-Audio {
    if (-not $script:manageVolume -and -not $script:userMuted) { return }
    try {
        [GbAudio]::SetVolume($script:origVol)
        # A mute the user made mid-alarm is left alone — they asked for quiet.
        if ($script:userMuted -or $script:origMute) { [GbAudio]::SetMute($true) }
    } catch { }
    Remove-Item $script:volFile -Force -ErrorAction SilentlyContinue
}

# Escalate toward the ceiling over the first six minutes, so the volume climbs
# with the siren density and the spoken "waiting N minutes".
function Step-Volume {
    if (-not $script:manageVolume) { return }
    try {
        # A mid-alarm mute means "quiet" — stand down from managing audio for
        # the rest of the run. The alarm keeps looping; typing still stops it.
        if ([GbAudio]::GetMute()) {
            $script:userMuted = $true
            $script:manageVolume = $false
            # Record the intent so alarm-stop.ps1's restore does not undo it.
            Set-Content -Path $script:volFile -Value "$($script:origVol) true"
            return
        }

        $cur = [GbAudio]::GetVolume()

        # Someone turned the knob down: a human is reacting. Adopt that as the
        # new ceiling. The 2-point slack absorbs rounding by the audio driver.
        if ($null -ne $script:lastSet -and $cur -lt ($script:lastSet - 2)) { $script:ceiling = $cur }

        $mins = [int][Math]::Floor(((Get-Date) - $script:started).TotalMinutes)
        if     ($mins -lt 1) { $target = 55 }
        elseif ($mins -lt 3) { $target = 65 }
        elseif ($mins -lt 6) { $target = 75 }
        else                 { $target = $script:VolCeiling }

        if ($target -lt $script:origVol) { $target = $script:origVol }   # never turn the user down
        if ($target -gt $script:ceiling) { $target = $script:ceiling }

        if ($target -gt $cur) { [GbAudio]::SetVolume($target); $script:lastSet = $target }
        else                  { $script:lastSet = $cur }
    } catch {
        $script:manageVolume = $false
    }
}

# --------------------------------------------------------------- sound + speech --
# Siren: two short system sounds cutting each other off every 0.22 s. If the
# sound files are missing, fall back to console beeps.
function New-Player($name) {
    $f = Join-Path $Media $name
    if (-not (Test-Path $f)) { return $null }
    try { $p = New-Object System.Media.SoundPlayer $f; $p.Load(); return $p } catch { return $null }
}
$sirenA = New-Player 'Windows Critical Stop.wav'
$sirenB = New-Player 'Windows Exclamation.wav'
$chimeA = New-Player 'Windows Notify System Generic.wav'
$chimeB = New-Player 'Windows Ding.wav'

function Play-Siren($pairs) {
    for ($i = 0; $i -lt $pairs; $i++) {
        if ($sirenA -and $sirenB) {
            $sirenA.Play(); Start-Sleep -Milliseconds 220
            $sirenB.Play(); Start-Sleep -Milliseconds 220
        } else {
            try { [Console]::Beep(988, 220); [Console]::Beep(659, 220) } catch { Start-Sleep -Milliseconds 440 }
        }
    }
    Start-Sleep -Milliseconds 600    # let the last sound finish
}

function Play-Chime($player) {
    if ($player) { try { $player.PlaySync() } catch { } }
}

# Speech is optional: without it the alarm is siren plus notification.
$synth = $null
$voiceA = $null; $voiceB = $null
try {
    Add-Type -AssemblyName System.Speech -ErrorAction Stop
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $synth.Rate = 1
    $synth.Volume = 100
    $voices = @($synth.GetInstalledVoices() | Where-Object { $_.Enabled } | ForEach-Object { $_.VoiceInfo.Name })
    if ($voices.Count -ge 1) { $voiceA = $voices[0]; $voiceB = $voices[0] }
    if ($voices.Count -ge 2) { $voiceB = $voices[1] }
} catch { $synth = $null }

function Speak($voice, $text) {
    if (-not $synth) { return }
    try { if ($voice) { $synth.SelectVoice($voice) } } catch { }
    try { $synth.Speak($text) } catch { }
}

# One notification at the start, so there is something to see as well as hear.
function Show-Toast($text) {
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        $esc = [Security.SecurityElement]::Escape($text)
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml("<toast><visual><binding template=`"ToastGeneric`"><text>Claude needs you</text><text>$esc</text></binding></visual><audio silent=`"true`"/></toast>")
        # Borrow PowerShell's registered app id; an unregistered id shows nothing.
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show(
            [Windows.UI.Notifications.ToastNotification]::new($xml))
    } catch { }
}

# Spoken form of how long the alarm has been running: "" for the first minute,
# then "1 minute", "7 minutes", "1 hour 12 minutes", ...
function Get-ElapsedPhrase {
    $total = [int][Math]::Floor(((Get-Date) - $script:started).TotalMinutes)
    $hrs = [Math]::Floor($total / 60); $mins = $total % 60
    $out = @()
    if ($hrs -eq 1) { $out += '1 hour' } elseif ($hrs -gt 1) { $out += "$hrs hours" }
    if ($mins -eq 1) { $out += '1 minute' } elseif ($mins -gt 1) { $out += "$mins minutes" }
    return ($out -join ' ')
}

# ------------------------------------------------------------------ run --
$started = Get-Date
switch -Regex ($cap) {
    '^(0|never|none|off)$' { $deadline = $null; break }
    '^\d+$'                { $deadline = $started.AddMinutes([int]$cap); break }
    default                { $deadline = $started.AddMinutes(60) }
}

# Stashed for alarm-stop.ps1, which restores these — on Windows the stop script
# kills this process outright, so the restore below only runs when the cap expires.
if ($manageVolume) {
    Set-Content -Path $volFile -Value "$origVol $(if ($origMute) { 'true' } else { 'false' })"
    if ($origMute) { try { [GbAudio]::SetMute($false) } catch { } }
}

Show-Toast $msg

try {
    $round = 0
    while ($true) {
        if ($deadline -and (Get-Date) -ge $deadline) { break }
        $round++

        # Escalation ladder: more siren, more speech, less silence between rounds.
        if     ($round -le 3) { $pairs = 4; $both = $false; $gap = 6 }
        elseif ($round -le 8) { $pairs = 6; $both = $true;  $gap = 3 }
        else                  { $pairs = 8; $both = $true;  $gap = 1 }

        Step-Volume
        Play-Siren $pairs

        $waited = Get-ElapsedPhrase
        $waitedLine = if ($waited) { " Waiting $waited." } else { '' }

        Play-Chime $chimeA
        Speak $voiceA "Attention. $msg.$waitedLine"

        if ($both) {
            Play-Chime $chimeB
            Speak $voiceB "$msg.$waitedLine"
        }

        Start-Sleep -Seconds $gap
    }
} finally {
    Restore-Audio
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}
