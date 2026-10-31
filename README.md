# Fishing Assistant

AutoHotkey v2 application for the Mirror Lake fishing minigame in Roblox.
It uses screen colors to time casting, detect bites, and reel with short
mouse clicks and delays. Tooltips display the current stage and diagnostics.

## Run

Launch `Fishing.exe`, or install AutoHotkey v2 and run `Fishing.ahk`.
Keep `Fishing.ini` beside the application. Open the fishing panel in Roblox
with **E**, then press **F6**. Keep Roblox in the foreground.

| Key | Action |
| --- | --- |
| F6 | Start or pause |
| F7 | Stop and release the mouse |
| F8 | Inspect pixel detection |
| F9 | Manually start combat recovery |
| Ctrl+Alt+Esc | Exit |

The application stops if Roblox loses focus or a stage times out.
It repeats casts by default; set `Repeat=0` for a single reel cycle.

## Settings

Edit `Fishing.ini`, then restart the application.

| Setting | Default | Meaning |
| --- | --- | --- |
| PulseMs | 75 | Maximum mouse-down duration per reel click, in milliseconds |
| MinimumGapMs | 90 | Minimum time between click starts, in milliseconds |
| SlackTarget | 0.065 | Click below this tension fraction; release early at the limit |
| CastTarget | 0.93 | Release the cast at this fraction of the bar |
| Repeat | 1 | Repeat after a reel cycle ends |

Longer reel pulses increase time spent reeling. The controller predicts the
next 30 ms of tension movement and cuts clicks short at the configured limit.

The `[Combat]` section controls recovery when the fishing panel closes after
a reel cycle, or the player's health drops after fishing has begun.
On health loss, it first presses Q to leave the fishing interface.
`Enabled=1` enables attack clicks every `ClickIntervalMs=120`.
After a minimum attack burst of `ReturnProbeMs=6000`, it waits for the target
health bar to disappear, then pauses attacks and repeatedly
holds E for one second, allowing the game's combat lock to clear. New damage
resumes attack clicks. It resumes fishing only after detecting the panel.
`TimeoutMs=45000` stops an encounter that cannot be recovered.
F7 and focus-loss handling release both the mouse and the interaction key.

The profile was tuned for a 1920 × 1008 client area. Different UI scaling,
aspect ratios, themes, or rod interfaces may require calibration.
The completed-cycle counter does not verify a fish reward; check the game's
Landed message or reward. Local diagnostics are written to `Fishing.log`.

## Validation

Repeated live tests verified gold-zone casts, bite detection, and fish rewards.
Reeling typically took about 4–5 seconds with the faster profile, compared
with roughly 11 seconds in earlier logs; fish difficulty varies.

F9 recovery was tested against the game's combat lock. A live Iron-Shell
Snapper / River Snapper encounter was also captured: the fishing panel closed,
the application attacked, the snapper disappeared, and held E restored fishing.
It caught a Grass Carp immediately afterward. Enemy target-bar detection uses
that captured snapper interface; other enemy interfaces may need calibration.

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
