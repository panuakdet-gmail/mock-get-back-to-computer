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

STATE="$HOME/.claude/.get-back-alarm"
SOUNDS=/System/Library/Sounds

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
msg="$1"
cap="$2"

# This process is its own group leader, so $$ is the pgid stop.sh will signal.
trap 'rm -f "$STATE/$$.pgid"; exit 0' TERM INT HUP EXIT

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

    i=0
    while [ "$i" -lt "$pairs" ]; do
        afplay "$SOUNDS/Sosumi.aiff" 2>/dev/null &
        sleep 0.22
        afplay "$SOUNDS/Basso.aiff" 2>/dev/null &
        sleep 0.22
        i=$((i + 1))
    done
    wait

    afplay "$SOUNDS/Submarine.aiff" 2>/dev/null
    speak "$VOICE_A" "Attention. $msg"

    if [ "$both" -eq 1 ]; then
        afplay "$SOUNDS/Glass.aiff" 2>/dev/null
        speak "$VOICE_B" "$msg"
    fi

    sleep "$gap"
done
