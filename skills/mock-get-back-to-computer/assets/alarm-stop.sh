#!/bin/bash
# alarm-stop.sh — silence every running alarm started by alarm-start.sh.
#
# Registered as a UserPromptSubmit hook, so it runs on EVERY prompt the user
# submits, in every session. Two consequences, both deliberate:
#   * it prints nothing on the normal path (hook stdout is injected into
#     Claude's context, and chatter here would pollute every single prompt)
#   * it always exits 0 and finishes in milliseconds
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

exit 0
