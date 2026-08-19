# get-back-to-computer

A skill for [Claude Code](https://claude.com/claude-code) that **shouts for you** when it gets stuck on something only you can do.

You set Claude working on something long, and you walk away — kitchen, garden, the next building. Ten seconds later it hits a login that wants a one-time code that expires in sixty seconds. It prints a polite line into the terminal and waits. You are not there to read it. The code expires, the session dies, and you come back forty minutes later to find nothing happened.

This skill makes noise instead. When Claude reaches the wall, it starts a siren — macOS system sounds, layered and repeating, plus a synthesised voice saying what it needs — and the siren **escalates** the longer you ignore it. The moment you sit down and type anything at all, it goes silent.

> **Claude Code** is Anthropic's coding assistant that runs in your terminal — the black window where you type commands. A **skill** is a set of instructions you can hand it on demand by typing a `/` command.

## The skill

| Command | What it does |
|---|---|
| `/mock-get-back-to-computer` | Sounds the alarm right now, or waits for a condition you describe in plain English and sounds it then. |

It is **manual only**, and that is the whole bargain. An alarm is rude, so Claude will never decide on its own to fill your house with a siren — it does it when you ask, and only for things you genuinely have to be present for.

## What you need

- **[Claude Code](https://claude.com/claude-code)** — Anthropic's assistant for your terminal. Install it first; nothing here works without it.
- **A Mac.** The alarm is built on three programs that come with macOS: `afplay` (plays a sound file), `say` (reads text aloud), and `osascript` (which is how it turns the volume up). There is nothing to install and nothing to buy, but there is also no Windows or Linux version.

You do **not** need to remember to turn the speakers up — the alarm does that itself, and puts your volume back afterwards. See [Your volume](#your-volume).

## Installing

There are two parts: the **skill** itself, and one small **hook** — a line of configuration that lets the alarm stop the instant you type. Option 1 does both for you.

### Option 1 — ask Claude Code to do it

The easiest route, and it needs no terminal knowledge at all. Open Claude Code in any folder and paste this:

```
Install the Claude Code skill from https://github.com/panuakdet-gmail/mock-get-back-to-computer
by adding it as a plugin marketplace, then install the "get-back-to-computer" plugin from it.
Afterwards, read that skill's SKILL.md and register the UserPromptSubmit hook it describes,
pointing at the installed copy of assets/alarm-stop.sh.
```

Claude Code will ask your permission before it changes anything.

### Option 2 — the built-in commands

Inside Claude Code, run these two:

```
/plugin marketplace add panuakdet-gmail/mock-get-back-to-computer
/plugin install get-back-to-computer@get-back-skills
```

The `plugin@marketplace` form is how Claude Code names a plugin: `get-back-to-computer` is the plugin, `get-back-skills` is the collection it came from.

Then set up the hook — see **The hook** below.

### Option 3 — by hand

Copy the skill folder into your personal skills directory:

```bash
git clone https://github.com/panuakdet-gmail/mock-get-back-to-computer.git
cp -R mock-get-back-to-computer/skills/mock-get-back-to-computer ~/.claude/skills/
chmod +x ~/.claude/skills/mock-get-back-to-computer/assets/*.sh
```

Skills are read when a session starts, so restart Claude Code afterwards. Then set up the hook.

### The hook

A **hook** is a command Claude Code runs automatically at a fixed moment. This one runs on `UserPromptSubmit` — every time you press Enter on a message — and all it does is kill any alarm that is sounding. That is why the siren stops the instant you type, even while Claude is still stuck mid-task and cannot act for itself.

Add it to `~/.claude/settings.json`:

```json
"hooks": {
  "UserPromptSubmit": [
    { "hooks": [ { "type": "command",
        "command": "/absolute/path/to/skills/mock-get-back-to-computer/assets/alarm-stop.sh",
        "timeout": 5 } ] }
  ]
}
```

Replace the path with wherever the file actually landed — `~/.claude/skills/…` if you installed by hand, or the plugin's own folder under `~/.claude/plugins/` if you installed as a plugin. It must be the full path, starting with `/`.

Easiest way to get this right, whichever option you used:

```
Register the alarm-stop.sh script from the mock-get-back-to-computer skill
as a UserPromptSubmit hook in my Claude Code settings.
```

Two things worth knowing. The two scripts **run where they are installed** — do not copy them somewhere else, because the hook hard-codes one path and a second copy would drift out of step with it. And register **only** `UserPromptSubmit`: a `Stop` hook would kill the alarm a few seconds after it started, which defeats the point.

Without the hook everything still works, except the alarm will not stop when you type — you would have to wait out the time limit. Worth the two minutes.

## Using it

### Call me back when something happens

Describe the moment you want to be fetched, in your own words:

```
/mock-get-back-to-computer call me when the deploy finishes
/mock-get-back-to-computer shout when the test suite goes red
/mock-get-back-to-computer alarm when you need my password
```

There is no fixed vocabulary — Claude works out how to watch for whatever you described, including the failure case. A watcher that only listens for success stays quiet through a crash, and silence is indistinguishable from *still working*.

### Call me back right now

No argument means you are already away and want fetching immediately:

```
/mock-get-back-to-computer
```

### Put a time limit on it

Fold it into the same sentence:

```
/mock-get-back-to-computer wait for the upload, for up to 10 minutes
/mock-get-back-to-computer keep going until I come
```

Unstated, the alarm gives up after **60 minutes** — a safety net so a forgotten alarm cannot run all night, not a schedule. "Keep going until I come" removes the limit entirely.

## What it sounds like

Three sound files that ship with macOS — `Sosumi`, `Basso`, `Submarine`, `Glass` — layered into a siren, then a voice reading a short line drawn from whatever Claude actually needs. It gets more insistent as the rounds go by:

| Rounds | Siren | Voice | Silence between |
|---|---|---|---|
| 1–3 | 4 beats | one voice | 6 seconds |
| 4–8 | 6 beats | two voices | 3 seconds |
| 9+ | 8 beats | two voices | 1 second |

From the second minute onward the voice also tells you **how long it has been waiting** — "Approve the login on your phone. Waiting 7 minutes." So when you walk in you know straight away whether you missed it by seconds or by an hour.

The spoken line is written for someone who cannot see the screen, so it says what to *do* rather than what happened — "Approve the login on your phone", not "authentication pending". Short codes get spelled out in the NATO alphabet, because text-to-speech mangles `A7K` but sails through "Alpha Seven Kilo". Secrets are never spoken: passwords, tokens, and full account numbers stay on the screen where only you can see them. When there is genuinely nothing specific to say, the voice falls back to *get back to the computer*.

When you arrive, the screen carries the detail — the code to read back, the button to press — in one line, without a wall of text between you and the thing that is waiting.

## Your volume

An alarm playing into a muted Mac is the worst thing this skill could do: it looks like it worked, and nobody heard a sound. So the alarm takes charge of the system volume for as long as it is running.

- **It unmutes and turns you up** if you are below its floor, and **escalates** as the wait drags on: 55% for the first minute, 65% up to three minutes, 75% up to six, then 85% and no higher. The top of the scale is left alone on purpose — it distorts small speakers, which makes the speech *harder* to understand, not easier.
- **It never turns you down.** Already sitting at 90%? It stays at 90%.
- **It backs off the moment you react.** Reach over and turn the volume down and the alarm takes that as its new ceiling and stops climbing. Mute it and it stops touching your audio altogether and leaves the mute alone — you asked for quiet.
- **It puts everything back.** Your original level and mute state are restored when the alarm stops, both by the alarm itself and again by the stop script, so a crash cannot leave your Mac loud.

The one thing no volume setting can fix is **where the sound comes out**. If your Mac is playing to headphones on the desk or a speaker in another room, no level is loud enough in the right place. The alarm is sound and nothing else — there is no second channel to fall back on.

## The rules it follows while you are away

- **Nothing irreversible.** An alarm means Claude is at a step needing a human, so it does not spend the wait sending, publishing, purchasing, deleting, or accepting terms on your behalf.
- **One alarm per thing.** It will not re-fire because you did not answer — the alarm is already escalating on its own.
- **Expiring things get a warning.** If a code or a signing window is running out, that goes in the spoken line too, and Claude will not burn a fresh one until you say you are ready.
- **No apology when you arrive.** It opens with what it needs, not with a recap of the noise it just made.

## What it produces

Nothing on disk except two short-lived files per running alarm, under `~/.claude/.get-back-alarm/`: a marker naming the running alarm, and a note of the volume and mute state to restore. Both are deleted when the alarm stops. No network calls, no accounts, no telemetry.

```
skills/mock-get-back-to-computer/
├── SKILL.md              the instructions Claude follows
└── assets/
    ├── alarm-start.sh    starts the escalating alarm, manages the volume, returns instantly
    └── alarm-stop.sh     silences every running alarm — this is what the hook runs
```

## Credits

Written from scratch by its author. It calls two programs Apple ships with macOS — `afplay` and `say` — and plays sound files that come with the operating system; none of that is copied or redistributed here.

## Licence

MIT — see [LICENSE](LICENSE). It covers the text and code in this repository. It says nothing about the macOS sound files the alarm plays, which are Apple's and stay on your own machine.
