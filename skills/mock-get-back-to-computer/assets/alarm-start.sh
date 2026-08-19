#!/bin/bash
# alarm-start.sh — start a detached, escalating audible alarm that keeps
# sounding until alarm-stop.sh kills it (or the safety cap expires).
#
# Usage: alarm-start.sh "<spoken message>" [max_minutes]
#   max_minutes  positive integer   stop after this long   (default 60)
#                0 | never | none   never stop on its own
#                anything else      treated as 60
#
# Returns immediately, printing the process-group id of the running alarm.
#
# An alarm nobody can hear has failed at its only job, so this also manages the
# system output volume: it unmutes, raises the level to a floor if it is below
# one, escalates that floor as the wait drags on, and puts everything back when
# it stops. It never turns the user down, and it backs off the moment they
# touch the volume themselves.

STATE="$HOME/.claude/.get-back-alarm"
SOUNDS=/System/Library/Sounds

VOL_CEILING=85          # never louder than this — the top of the scale distorts
                        # cheap speakers and makes the speech LESS intelligible

# ---------------------------------------------------------------- launcher --
# Called without --run: spawn the loop in its OWN process group and return.
# `set -m` (job control) is what puts the background job in a fresh process
# group; afplay/say children then inherit it, so one `kill -TERM -PGID`
# silences everything at once.
if [ "$1" != "--run" ]; then
    msg="${1:-get back to the computer}"
    cap="${2:-60}"

    mkdir -p "$STATE" || exit 1

    set -m
    nohup "$0" --run "$msg" "$cap" >/dev/null 2>&1 &
    pgid=$!
    set +m
    disown 2>/dev/null

    echo "$pgid" > "$STATE/$pgid.pgid"
    echo "$pgid"
    exit 0
fi

# --------------------------------------------------------------- the alarm --
shift
msg="${1%.}"
cap="$2"

# ------------------------------------------------------------ output volume --
vol_get()  { osascript -e 'output volume of (get volume settings)' 2>/dev/null; }
mute_get() { osascript -e 'output muted of (get volume settings)' 2>/dev/null; }
vol_set()  { osascript -e "set volume output volume $1" 2>/dev/null; }
unmute()   { osascript -e 'set volume without output muted' 2>/dev/null; }
mute_on()  { osascript -e 'set volume with output muted' 2>/dev/null; }

orig_vol=$(vol_get)
orig_mute=$(mute_get)
user_muted=0
last_set=""
ceiling=$VOL_CEILING

# Some output devices report "missing value" instead of a number; if we cannot
# read the level we do not touch it, and the alarm plays at whatever is set.
case "$orig_vol" in
    ''|*[!0-9]*) manage_volume=0 ;;
    *)           manage_volume=1 ;;
esac

restore_audio() {
    [ "$manage_volume" -eq 1 ] || [ "$user_muted" -eq 1 ] || return 0
    [ -n "$orig_vol" ] && vol_set "$orig_vol"
    # A mute the user made mid-alarm is left alone — they asked for quiet.
    if [ "$user_muted" -eq 1 ] || [ "$orig_mute" = true ]; then mute_on; fi
    rm -f "$STATE/$$.vol"
}

# Escalate toward the ceiling over the first six minutes, so the volume climbs
# with the siren density and the spoken "waiting N minutes".
ramp_volume() {
    [ "$manage_volume" -eq 1 ] || return 0

    # A mid-alarm mute means "quiet" — stand down from managing audio for the
    # rest of the run. The alarm keeps looping; typing is still what stops it.
    if [ "$(mute_get)" = true ]; then
        user_muted=1
        manage_volume=0
        # Record the intent so alarm-stop.sh's backstop restore does not undo
        # it — otherwise whichever of the two runs last decides.
        printf '%s %s\n' "$orig_vol" "true" > "$STATE/$$.vol"
        return 0
    fi

    local cur target mins
    cur=$(vol_get)
    case "$cur" in ''|*[!0-9]*) return 0 ;; esac

    # Someone turned the knob down: a human is reacting. Adopt that as the new
    # ceiling and stop climbing past it. The 2-point slack absorbs the rounding
    # macOS applies when it maps the level onto hardware steps.
    if [ -n "$last_set" ] && [ "$cur" -lt $(( last_set - 2 )) ]; then
        ceiling=$cur
    fi

    mins=$(( ( $(date +%s) - started ) / 60 ))
    if   [ "$mins" -lt 1 ]; then target=55
    elif [ "$mins" -lt 3 ]; then target=65
    elif [ "$mins" -lt 6 ]; then target=75
    else                         target=$VOL_CEILING
    fi

    [ "$target" -lt "$orig_vol" ] && target=$orig_vol    # never turn the user down
    [ "$target" -gt "$ceiling" ]  && target=$ceiling

    if [ "$target" -gt "$cur" ]; then
        vol_set "$target"
        last_set=$target
    else
        last_set=$cur
    fi
}

# This process is its own group leader, so $$ is the pgid stop.sh will signal.
trap 'restore_audio; rm -f "$STATE/$$.pgid"; exit 0' TERM INT HUP EXIT

# Stashed for alarm-stop.sh, which restores these too — the trap covers the
# normal path, the file covers a kill -9, a crash, or a reboot mid-alarm.
if [ "$manage_volume" -eq 1 ]; then
    printf '%s %s\n' "$orig_vol" "$orig_mute" > "$STATE/$$.vol"
    [ "$orig_mute" = true ] && unmute
fi

started=$(date +%s)

# Spoken form of how long the alarm has been running: "" for the first minute,
# then "one minute", "seven minutes", "one hour twelve minutes", ...
elapsed_phrase() {
    local secs=$(( $(date +%s) - started ))
    local mins=$(( secs / 60 ))
    local hrs=$(( mins / 60 ))
    mins=$(( mins % 60 ))
    local out=""
    if [ "$hrs" -gt 0 ]; then
        out="$hrs hour"; [ "$hrs" -gt 1 ] && out="$hrs hours"
    fi
    if [ "$mins" -gt 0 ]; then
        if [ "$mins" -eq 1 ]; then out="$out 1 minute"; else out="$out $mins minutes"; fi
    fi
    echo "${out# }"
}

case "$cap" in
    0|never|none|off)  deadline=0 ;;
    ''|*[!0-9]*)       deadline=$(( $(date +%s) + 60 * 60 )) ;;
    *)                 deadline=$(( $(date +%s) + cap * 60 )) ;;
esac

# Fall back to the default voice if a named one is not installed.
have_voice() { say -v '?' 2>/dev/null | awk -v v="$1" '$1 == v { f = 1 } END { exit !f }'; }
have_voice Samantha && VOICE_A="Samantha" || VOICE_A=""
have_voice Daniel   && VOICE_B="Daniel"   || VOICE_B=""

speak() {  # speak <voice> <text>
    if [ -n "$1" ]; then say -v "$1" -r 190 "$2" 2>/dev/null || say -r 190 "$2" 2>/dev/null
    else say -r 190 "$2" 2>/dev/null
    fi
}

round=0
while :; do
    [ "$deadline" -ne 0 ] && [ "$(date +%s)" -ge "$deadline" ] && break
    round=$((round + 1))

    # Escalation ladder: more siren, more speech, less silence between rounds.
    if   [ "$round" -le 3 ]; then pairs=4; both=0; gap=6
    elif [ "$round" -le 8 ]; then pairs=6; both=1; gap=3
    else                          pairs=8; both=1; gap=1
    fi

    ramp_volume

    i=0
    while [ "$i" -lt "$pairs" ]; do
        afplay "$SOUNDS/Sosumi.aiff" 2>/dev/null &
        sleep 0.22
        afplay "$SOUNDS/Basso.aiff" 2>/dev/null &
        sleep 0.22
        i=$((i + 1))
    done
    wait

    waited=$(elapsed_phrase)
    if [ -n "$waited" ]; then waited_line=" Waiting $waited."; else waited_line=""; fi

    afplay "$SOUNDS/Submarine.aiff" 2>/dev/null
    speak "$VOICE_A" "Attention. $msg.$waited_line"

    if [ "$both" -eq 1 ]; then
        afplay "$SOUNDS/Glass.aiff" 2>/dev/null
        speak "$VOICE_B" "$msg.$waited_line"
    fi

    sleep "$gap"
done
