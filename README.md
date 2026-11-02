# Fishing Assistant

AutoHotkey v2 application for fishing in Roblox, including the mounted
Waterfall Gorge profile. It uses screen colors to time casting and detect bites.
All game input is keyboard-only: E for fishing, T for artifact volley, and 9
for the fishing rod. It emits no mouse-button input and preserves the mount.
Tooltips display the current stage and diagnostics.

## Run

Launch `Fishing.exe`, or install AutoHotkey v2 and run `Fishing.ahk`.
Keep `Fishing.ini` and `CatchLogger.ps1` beside the application. Press **F6**
with Roblox focused. The app equips the rod with **9** if its fishing panel is
closed. Slot 9 must contain the rod, and T must trigger the auto-aim artifact
volley. Keep Roblox in the foreground.

| Key | Action |
| --- | --- |
| F6 | Start or pause |
| F7 | Stop and release held game keys |
| F8 | Inspect pixel detection |
| F9 | Manually start combat recovery |
| F10 | Open persistent catch history |
| Ctrl+Alt+Esc | Exit |

The application stops if Roblox loses focus or a stage times out.
It repeats casts by default; set `Repeat=0` for a single reel cycle.

After every catch, the app verifies that the fishing panel is still present
before casting again. It also watches for the rod being put away during casting,
bite waiting, or hooking. A missing panel is debounced for 650 ms, held E is
released, and slot 9 restores the rod. An already visible panel is not toggled
off. Enemy health bars or red encounter introductions route to T combat instead;
ordinary movement or rod stowing does not trigger attack spam. Rod recovery
starts a fresh timeout, rather than inheriting an old combat timer.

## Settings

Edit `Fishing.ini`, then restart the application.

| Setting | Default | Meaning |
| --- | --- | --- |
| PulseMs | 75 | Maximum E hold per reel pulse, in milliseconds |
| MinimumGapMs | 90 | Minimum time between E pulse starts, in milliseconds |
| SlackTarget | 0.065 | Reel below this tension fraction; release early at the limit |
| CastTarget | 0.93 | Release the cast at this fraction of the bar |
| Repeat | 1 | Repeat after a reel cycle ends |

Longer reel pulses increase time spent reeling. The controller predicts the
next 30 ms of tension movement and releases E at the configured limit.

The `[Combat]` section controls recovery when the fishing panel closes after
a reel cycle, or the player's health drops after fishing has begun.
On health loss, it first presses Q to leave the fishing interface.
`Enabled=1` enables T artifact-volley presses every `AttackIntervalMs=120`.
After a minimum attack burst of `ReturnProbeMs=6000`, it waits for the target
health bar to disappear, then pauses attacks and repeatedly
presses rod slot 9, allowing the game's combat lock to clear. New damage
resumes artifact volley. It resumes fishing only after detecting the panel.
`TimeoutMs=45000` stops an encounter that cannot be recovered.
F7, exit, and focus-loss handling release E, T, 9, and the fishing cancel key.

## Catch history and Discord

Each reel result queues a crop of the central reward card. A separate Windows
PowerShell worker uses built-in Windows OCR to read the catch name and weight,
then saves the event before attempting a Discord delivery. Reeling does not
wait for OCR or the network. Fish, non-fish rewards, and readable encounters
are recorded separately from unreadable results; unreadable text is never
invented as a catch name.

Press **F10** to view catches, weights, times, reel durations, and delivery
status. Opening history takes focus and pauses active fishing; close it and
press F6 in Roblox to resume. `CatchHistory.tsv` is a tab-separated export,
and `catches/` contains each event's JSON and reward images. These files persist
between sessions and are excluded from Git. Unsaved queued events are processed
on the next application launch.

To enable Discord, copy `Fishing.secrets.example.ini` to
`Fishing.secrets.ini` and set `WebhookURL` in its `[Discord]` section.
The secrets file is excluded from Git and is not embedded in the executable.
With no webhook configured, local history still works. Notifications contain
the parsed catch details and, by default, a reward-card image. No full desktop
or Discord screenshots are uploaded. Set `[History] IncludeRewardImage=0` to
send text only, or `Enabled=0` to disable catch capture.

The worker uses Windows PowerShell 5.1, Windows OCR, and an installed English
OCR language; no Python installation or bot token is required. It honors
Discord rate-limit responses, records delivery failures locally, and does not
automatically repost persisted events after an ambiguous network failure.

```text
powershell.exe -NoProfile -File CatchLogger.ps1 -TestWebhook
powershell.exe -NoProfile -File tests/Test-CatchParser.ps1
powershell.exe -NoProfile -File tests/Test-KeyboardControls.ps1
```

The first command sends a clearly labelled connection test, not a catch.

The profile was tuned for a 1920 × 1008 client area. Different UI scaling,
aspect ratios, themes, or rod interfaces may require calibration.
The completed-cycle counter does not verify a fish reward; check the game's
Landed message or reward. Local diagnostics are written to `Fishing.log`.

## Validation

Repeated live tests verified gold-zone casts, bite detection, and fish rewards.
Reeling typically took about 4–5 seconds with the faster profile, compared
with roughly 11 seconds in earlier logs; fish difficulty varies.

The mounted profile was live-tested at Waterfall Gorge. It caught fish using E,
handled a Water Ghoul with T, equipped the rod again with 9, and resumed fishing.
The mount remained at 140/140 health. A regression check rejects mouse-input
commands. Enemy target-bar detection uses the game's red bar below the compass;
different enemy interfaces may still need calibration.

Rod recovery was live-tested by putting the rod away during a bite wait. The
app detected the lost panel, re-equipped slot 9, resumed casting about a second
later, and continued catching fish. Repeated normal catches verified that an
already equipped rod is left out. The optional live regression command is
`Fishing.ahk --test 60 --test-rod-loss`; normal startup never runs this test.

Catch logging was live-tested with fish weights, a new-record reward, and a
non-fish purse reward. Local history, Discord embeds with reward images, and
duplicate-event suppression were verified. Parser regression checks cover
ordinary fish, record messages, missing weights, encounters, and non-reward text.

```text
AutoHotkey64.exe /ErrorStdOut Fishing.ahk --check
AutoHotkey64.exe /ErrorStdOut Fishing.ahk --test
```

`--check` validates loading without starting automation. `--test` activates
Roblox, attempts to open the fishing panel if absent, starts automation, and
exits after 35 seconds. An optional second argument sets a test duration in
seconds, up to 900: `Fishing.ahk --test 600`.
`--run` activates Roblox and starts without a test timeout. Normal launch
always waits for F6.
For live reference capture, `--run --capture-encounters` delays the first
attack by 1.2 seconds. Normal runs attack immediately.

## Build the executable

Use Ahk2Exe with `Fishing.ahk` as the input and the AutoHotkey v2 64-bit
executable as the base. No video-decoding tools or reference images are
required to run the application.
