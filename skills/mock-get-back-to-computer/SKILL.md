---
name: mock-get-back-to-computer
description: >-
  Summon the user back to the computer with an escalating audible alarm — a
  siren of macOS system sounds plus a spoken message — when Claude reaches a
  point it cannot pass without them: a code to read off the screen, a prompt to
  approve, a device to touch, a credential only they can type. The user names
  the condition to wait for; Claude watches for it, fires the alarm, and the
  alarm dies the instant the user types anything. The spoken message is drawn
  from context, falling back to "get back to the computer", and each round also
  says how long the alarm has been waiting. The alarm manages the system output
  volume so it cannot fail silently on a muted or quiet Mac, escalating the
  level as the wait drags on and restoring it afterwards.
  MANUAL TRIGGER ONLY: apply when the user invokes /mock-get-back-to-computer or
  explicitly asks for this alarm by name. Do NOT apply automatically whenever a
  task needs human input — most waits do not warrant filling the room with a
  siren, and an unrequested alarm is far worse than a silent prompt.
---

# Get back to the computer

Claude regularly hits a wall only the human can climb: a one-time code that expires in a minute, a login that wants a password, a phone app that must approve something, a physical key that must be touched. If the human is in another room, terminal output is invisible and a notification banner is silent. This skill makes noise instead — a siren that escalates until they return, and stops the moment they do.

The bargain is deliberate: an alarm is rude, so it must be **asked for**, must fire **only when the human is genuinely required**, and must **shut up instantly** when they arrive.

## Requirements

macOS only — it relies on `afplay`, `say`, and `osascript`. No Homebrew packages, no network.

The instant-stop behaviour depends on a hook registered in `~/.claude/settings.json`:

```json
"hooks": {
  "UserPromptSubmit": [
    { "hooks": [ { "type": "command",
        "command": "/absolute/path/to/skills/mock-get-back-to-computer/assets/alarm-stop.sh" } ] }
  ]
}
```

The harness runs that on every prompt submission, which is why the alarm dies even while Claude is blocked inside a long tool call. **If the hook is missing, install it before using the skill** — use the `update-config` skill rather than hand-editing the JSON.

Unlike most skills here, `assets/alarm-start.sh` and `assets/alarm-stop.sh` **run in place and must not be copied elsewhere** — the hook hard-codes one absolute path, and a second copy would drift out of sync with it. Register only `UserPromptSubmit`; a `Stop` hook would kill the alarm seconds after starting it.

## What it does to your volume

An alarm playing into a muted Mac is the worst outcome this skill has: it looks like it worked, and nobody heard it. `afplay -v` and `say`'s `[[volm]]` cannot rescue that — both are relative to the system level — so the alarm manages the system output volume directly.

- **Unmutes** at the start, and raises the level if it is below the ramp's floor.
- **Escalates** with the wait: 55% for the first minute, 65% to three minutes, 75% to six, then 85% and hold. The ceiling is 85 on purpose — the top of the scale distorts small speakers, which makes the speech *less* intelligible, not more.
- **Never turns the user down.** Already at 90%? It stays at 90%.
- **Backs off when a human reacts.** If the level drops below what the alarm last set, someone turned the knob: that becomes the new ceiling and the escalation stops there. A mute mid-alarm means "quiet" — the alarm stops touching audio entirely for the rest of the run and leaves the mute in place.
- **Puts it back.** The original level and mute state are restored when the alarm stops. `alarm-stop.sh` restores them too, from a file in the state directory, so a `kill -9` or a crash cannot leave the Mac loud.

If the output device does not report a numeric level (`missing value`), the alarm leaves volume alone and plays at whatever is set.

**Volume is per output device, and that is the one failure this cannot fix.** If audio is routed to headphones on the desk or a speaker in another room, no level is loud enough in the right place. That is what makes a `PushNotification` alongside the alarm worth sending.

## Argument convention

```
/mock-get-back-to-computer <condition, in plain English>
```

The **condition is whatever the user describes** — there is no fixed vocabulary. "when the deploy finishes", "when the test suite goes red", "when you need my password", "when that upload hits 100%".

**No argument means alarm right now.** They are already away and want to be called back.

The user may fold a time limit into the same sentence — "for up to 10 minutes", "keep going until I come" — which becomes the `max_minutes` argument. **Unstated means 60.** Use `0` for "never give up".

## Procedure

### 1. Decide what to say

Derive the spoken line from what is actually happening. It is read aloud by a speech synthesiser to someone who cannot see the screen, so:

- **Keep it under about 15 words.** One sentence naming what is needed.
- **Say what to do, not what happened.** "Approve the login on your phone" beats "authentication pending".
- **Spell short alphanumeric codes with the NATO alphabet** so they survive text-to-speech — `A7K` becomes "Alpha Seven Kilo". Digits read fine on their own.
- **Never speak a secret.** Passwords, tokens, and full account numbers do not go into a sentence broadcast across the house.

**When context gives you nothing to say, use exactly `get back to the computer`.** Do not invent detail to sound helpful.

### 2. Pick a watch strategy

Match the condition to the cheapest primitive that fits:

| Condition shape | Use |
|---|---|
| Already true, or a bare nudge | Fire immediately — no watching needed |
| A one-shot event (build ends, file appears, port opens) | `Bash` with `run_in_background` and an `until` loop that **exits** when true; fire when the completion notification arrives |
| A signal that recurs, where each occurrence matters | `Monitor` |
| Something only Claude can see (a screen changes, a value appears in a page) | Poll inside the turn, then fire |

Do not point `Monitor` at a condition that happens once — an unbounded watcher stays armed long after the event, burning its whole timeout. Conversely, do not use a backgrounded `until` loop for something that must report repeatedly.

Whatever you choose, **cover the failure path too**. A watcher that only matches success stays silent through a crash, and silence is indistinguishable from "still working" — the user waits forever for an alarm that will never come.

### 3. Fire

```bash
assets/alarm-start.sh "<the spoken message>" [max_minutes]
```

It handles volume itself — nothing to pass, nothing to check first.

From the second minute on, every spoken round appends how long it has been
waiting — "Approve the login on your phone. Waiting 7 minutes." — so a user
walking in knows whether they missed it by seconds or by an hour. Nothing to
pass in; the script times itself.

It detaches and **returns immediately**, printing the process-group id. Do **not** wrap it in `run_in_background` and do not wait on it.

Consider sending a `PushNotification` alongside it: sound reaches the next room, a push reaches the next building.

### 4. Say why, on screen

Print one line naming exactly what you need, including any code or value the user must read back, and note the wall-clock time the alarm started so the elapsed figure spoken aloud has a written counterpart. If the alarm raised the volume or unmuted, say so in the same place — silent audio changes are the kind of thing that makes people distrust a tool. Someone walking in cold should learn what is wanted without scrolling. Then stop talking — a returning user does not want a wall of text between them and the thing that is waiting.

### 5. Stand down

The hook silences the alarm the moment the user types. **You do not need to stop it yourself**, and you should not spend a tool call doing so.

When they answer, open with what you needed. Do not recap the alarm, apologise for the noise, or narrate the wait.

If the noise continues after the user has spoken, the hook is broken. **Say so plainly and offer to repair it** — do not paper over it by calling `alarm-stop.sh` on every turn.

## Rules

1. **Only for things the user must physically do.** If you can finish it alone, finish it alone. Waiting on a slow build is not by itself a reason to make noise.
2. **One alarm per condition.** Do not re-fire because the first attempt went unanswered — it is already looping and escalating on its own.
3. **Nothing irreversible while they are away.** With an alarm pending you are, by definition, at a step that needs a human. Do not spend the wait making changes they have not seen — no sending, publishing, purchasing, deleting, or accepting terms.
4. **Time-boxed opportunities get a warning.** If the thing waiting expires (a code, a session, a signing window), say so in both the spoken line and the on-screen line, and do not burn a fresh one until they confirm they are ready.
5. **The cap is a safety net, not a schedule.** It exists so a forgotten alarm cannot run all night. Never pick a short cap hoping to be polite — an alarm that gives up before the user arrives has failed at its only job.

## When you're done

Report in this shape:

- **What was waiting** — the thing that needed them, in one line.
- **What I did while waiting** — or "nothing" if you correctly sat still.
- **Still needed** — what you want them to do now.

No recap of the alarm itself, no apology for the noise.
