FISHING ASSISTANT - AutoHotkey v2

Launch Fishing.exe, or launch Fishing.ahk with AutoHotkey v2.
In Roblox, open the fishing panel with E, then press F6.
Keep Roblox in the foreground and the fishing panel unobstructed.

F6             Start / pause
F7             Stop and release the mouse
F8             Show pixel detection diagnostics in the tooltip and log
Ctrl+Alt+Esc   Exit and release the mouse

The tooltip shows the current stage, detected tension marker, panel colors,
and number of completed reel cycles. A cycle ending does not by itself prove
a successful catch: confirm the game's Landed message / fish reward.

The script holds left click for the cast, releases in the gold zone, waits for
the red float to dip, clicks to hook, then reels with short mouse pulses and
gaps based on the white tension marker. It repeats after a reel cycle ends.
It stops automatically if Roblox loses focus or a stage times out.

Fishing.ini settings (restart the script after editing):
PulseMs          Mouse-down duration of each reel click (default 32 ms).
MinimumGapMs     Minimum time between the starts of reel clicks (65 ms).
SlackTarget      Click below this fraction of the tension bar (0.045).
                 Lower it to reduce tension; increase slightly if too slack.
CastTarget       Release at this fraction of the casting bar (0.93).
Repeat           1 repeats; 0 stops after a single reel cycle.

The initial profile comes from the supplied 1920 x 1008 recording and the
current maximized Roblox window. It scales with client dimensions, but a
different Roblox UI scale, rod UI, theme, or aspect ratio may need adjustment.
F8 helps identify a missing panel or marker. Avoid moving while fishing.

Fishing.log records state transitions and calibration diagnostics.
The tools directory and reference images were used to inspect the recording;
the running application requires only Fishing.exe and Fishing.ini (or the
Fishing.ahk source with AutoHotkey v2 installed).

Developer checks:
AutoHotkey64.exe /ErrorStdOut Fishing.ahk --check
AutoHotkey64.exe /ErrorStdOut Fishing.ahk --test
--check validates loading without running the automation.
--test activates Roblox, attempts a held E interaction if the panel is absent,
starts the automation, and exits after 35 seconds.
