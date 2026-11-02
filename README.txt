FISHING ASSISTANT - AutoHotkey v2

Launch Fishing.exe, or launch Fishing.ahk with AutoHotkey v2.
Press F6 with Roblox focused. The app equips your fishing rod from slot 9.
All game input is keyboard-only: E fishes, T fires artifact volley, 9 equips
the rod. No mouse-button input is emitted, preserving your mounted state.
Keep Roblox in the foreground and the fishing panel unobstructed.

F6             Start / pause
F7             Stop and release held game keys
F8             Show pixel detection diagnostics in the tooltip and log
F9             Manually start combat recovery
F10            Open persistent catch history (takes focus and pauses fishing)
Ctrl+Alt+Esc   Exit and release held game keys

The tooltip shows the current stage, detected tension marker, panel colors,
and number of completed reel cycles. A cycle ending does not by itself prove
a successful catch: confirm the game's Landed message / fish reward.

The script holds E for the cast, releases in the gold zone, waits for
the red float to dip, presses E to hook, then reels with short E pulses and
gaps based on the white tension marker. It repeats after a reel cycle ends.
It stops automatically if Roblox loses focus or a stage times out.

After every catch the app checks that the rod's fishing panel is present.
If movement or another interruption puts the rod away, it releases E and uses
slot 9 to restore fishing, rather than waiting for the bite timer to expire.
It does not toggle slot 9 when the panel is already visible. Detected enemy
bars or encounter cards trigger T combat; rod loss alone does not.

Fishing.ini settings (restart the script after editing):
PulseMs          Maximum E hold per reel pulse (default 75 ms).
MinimumGapMs     Minimum time between E pulse starts (90 ms).
SlackTarget      Reel below this tension fraction; release at the limit (0.065).
                 Lower it to reduce tension; increase slightly if too slack.
CastTarget       Release at this fraction of the casting bar (0.93).
Repeat           1 repeats; 0 stops after a single reel cycle.

Combat settings:
Enabled          1 enables recovery after a panel interruption or health loss.
AttackIntervalMs Time between T artifact-volley presses (120 ms).
ReturnProbeMs    Attack-burst duration before waiting for combat clear (6000 ms).
TimeoutMs        Stop if recovery is not confirmed within this time (45000 ms).
The application resumes fishing only after detecting the fishing panel again.
It pauses volley while retrying rod slot 9 so the combat lock can expire.
It keeps attacking if the red target-health bar is still visible.
New health loss resumes artifact volley during this quiet period.
Stopping, exiting, or losing focus releases E, T, 9, and Q.

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
--test activates Roblox, equips the rod with 9 if the panel is absent,
starts the automation, and exits after 35 seconds. Supply a second argument
to change the test duration, up to 900 seconds: Fishing.ahk --test 600.
--run starts immediately without a test timeout. Normal launch waits for F6.
--test 60 --test-rod-loss performs one controlled rod-stow recovery test.
