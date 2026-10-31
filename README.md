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
| Ctrl+Alt+Esc | Exit |

The application stops if Roblox loses focus or a stage times out.
It repeats casts by default; set `Repeat=0` for a single reel cycle.

## Settings

Edit `Fishing.ini`, then restart the application.

| Setting | Default | Meaning |
| --- | --- | --- |
| PulseMs | 32 | Mouse-down duration per reel click, in milliseconds |
| MinimumGapMs | 65 | Minimum time between click starts, in milliseconds |
| SlackTarget | 0.045 | Click when tension is below this fraction of the bar |
| CastTarget | 0.93 | Release the cast at this fraction of the bar |
| Repeat | 1 | Repeat after a reel cycle ends |

The profile was tuned for a 1920 × 1008 client area. Different UI scaling,
aspect ratios, themes, or rod interfaces may require calibration.
The completed-cycle counter does not verify a fish reward; check the game's
Landed message or reward. Local diagnostics are written to `Fishing.log`.

## Validation

Gold-zone releases, bite detection, and two reel cycles were tested against
the live client. The final sampled green progress in those cycles was 95%
and 96% before the reel interface ended.

```text
AutoHotkey64.exe /ErrorStdOut Fishing.ahk --check
AutoHotkey64.exe /ErrorStdOut Fishing.ahk --test
```

`--check` validates loading without starting automation. `--test` activates
Roblox, attempts to open the fishing panel if absent, starts automation, and
exits after 35 seconds.

## Build the executable

Use Ahk2Exe with `Fishing.ahk` as the input and the AutoHotkey v2 64-bit
executable as the base. No video-decoding tools or reference images are
required to run the application.
