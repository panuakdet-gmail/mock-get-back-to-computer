#!/bin/bash
# alarm-stop.sh — silence every running alarm started by alarm-start.sh.
#
# Registered as a UserPromptSubmit hook, so it runs on EVERY prompt the user
# submits, in every session. Two consequences, both deliberate:
#   * it prints nothing on the normal path (hook stdout is injected into
#     Claude's context, and chatter here would pollute every single prompt)
#   * it always exits 0 and finishes in milliseconds
#
# It also restores the system output volume that alarm-start.sh raised. The
# alarm restores that itself on the normal path; this is the backstop for a
# kill -9, a crash, or a reboot that left the Mac loud.
#
# Takes no arguments. Safe to run when no alarm exists.

STATE="$HOME/.claude/.get-back-alarm"
[ -d "$STATE" ] || exit 0

for f in "$STATE"/*.pgid; do
    [ -e "$f" ] || continue                      # no matches: the glob is literal
    pgid=$(basename "$f" .pgid)

    case "$pgid" in
        ''|*[!0-9]*) rm -f "$f"; continue ;;     # junk filename
    esac
    # Guard hard: `kill -TERM -1` would signal every process the user owns.
    [ "$pgid" -gt 1 ] 2>/dev/null || { rm -f "$f"; continue; }

    # Negative pgid signals the whole group, which is what takes afplay and
    # say down with the loop. Failure is normal here — a stale file just means
    # the alarm already ended.
    kill -TERM -"$pgid" 2>/dev/null
    rm -f "$f"
done

# Volume last, so a still-dying alarm cannot raise it again after we put it
# back. The file holds "<level> <muted>" as they were before the alarm began.
for f in "$STATE"/*.vol; do
    [ -e "$f" ] || continue
    read -r vol muted < "$f"
    case "$vol" in
        ''|*[!0-9]*) rm -f "$f"; continue ;;
    esac
    osascript -e "set volume output volume $vol" 2>/dev/null
    [ "$muted" = true ] && osascript -e 'set volume with output muted' 2>/dev/null
    rm -f "$f"
done

exit 0
