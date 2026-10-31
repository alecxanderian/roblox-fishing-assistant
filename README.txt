FISHING ASSISTANT - AutoHotkey v2

Launch Fishing.exe, or launch Fishing.ahk with AutoHotkey v2.
In Roblox, open the fishing panel with E, then press F6.
Keep Roblox in the foreground and the fishing panel unobstructed.

F6             Start / pause
F7             Stop and release the mouse
F8             Show pixel detection diagnostics in the tooltip and log
F9             Manually start combat recovery
F10            Open persistent catch history (takes focus and pauses fishing)
Ctrl+Alt+Esc   Exit and release the mouse

The tooltip shows the current stage, detected tension marker, panel colors,
and number of completed reel cycles. A cycle ending does not by itself prove
a successful catch: confirm the game's Landed message / fish reward.

The script holds left click for the cast, releases in the gold zone, waits for
the red float to dip, clicks to hook, then reels with short mouse pulses and
gaps based on the white tension marker. It repeats after a reel cycle ends.
It stops automatically if Roblox loses focus or a stage times out.

Fishing.ini settings (restart the script after editing):
PulseMs          Maximum mouse-down duration per reel click (default 75 ms).
MinimumGapMs     Minimum time between the starts of reel clicks (90 ms).
SlackTarget      Click below this tension fraction; release at the limit (0.065).
                 Lower it to reduce tension; increase slightly if too slack.
CastTarget       Release at this fraction of the casting bar (0.93).
Repeat           1 repeats; 0 stops after a single reel cycle.

Combat settings:
Enabled          1 enables recovery after a panel interruption or health loss.
ClickIntervalMs  Time between attack clicks (120 ms).
ReturnProbeMs    Attack-burst duration before waiting for combat clear (6000 ms).
TimeoutMs        Stop if recovery is not confirmed within this time (45000 ms).
The application resumes fishing only after detecting the fishing panel again.
It pauses attacks while retrying held E so the combat lock can expire.
It keeps attacking if the red target-health bar is still visible.
New health loss resumes attack clicks during this quiet period.
Stopping, exiting, or losing focus releases both left click and E.

The initial profile comes from the supplied 1920 x 1008 recording and the
current maximized Roblox window. It scales with client dimensions, but a
different Roblox UI scale, rod UI, theme, or aspect ratio may need adjustment.
F8 helps identify a missing panel or marker. Avoid moving while fishing.

Fishing.log records state transitions and calibration diagnostics.
The tools directory and reference images were used to inspect the recording;
the running application requires Fishing.exe, Fishing.ini, and CatchLogger.ps1
(or the Fishing.ahk source with AutoHotkey v2 installed).

CATCH HISTORY AND DISCORD

CatchHistory.tsv contains the history; catches/ contains event JSON and cropped
reward images. F10 shows the history in the app. Close history and press F6 in
Roblox to resume fishing. Local history works without a Discord webhook.

Copy Fishing.secrets.example.ini to Fishing.secrets.ini and set WebhookURL in
the Discord section. The secrets file, history, and images are excluded from
GitHub. No secret is embedded in the executable. The worker sends catch details
and a cropped reward card; it never uploads the full desktop or Discord screen.

History settings:
Enabled             1 enables catch capture and OCR (default).
IncludeRewardImage  1 attaches the verified reward crop; 0 sends text only.

Windows PowerShell 5.1 and built-in Windows OCR handle logging in a separate
worker, so network and OCR do not block reeling. Delivery status is recorded
locally. Rate limits are retried; ambiguous deliveries are not automatically
reposted. Unsaved queued events are processed on the next application launch.

Developer checks:
AutoHotkey64.exe /ErrorStdOut Fishing.ahk --check
AutoHotkey64.exe /ErrorStdOut Fishing.ahk --test
--check validates loading without running the automation.
--test activates Roblox, attempts a held E interaction if the panel is absent,
starts the automation, and exits after 35 seconds. Supply a second argument
to change the test duration, up to 900 seconds: Fishing.ahk --test 600.
--run starts immediately without a test timeout. Normal launch waits for F6.
