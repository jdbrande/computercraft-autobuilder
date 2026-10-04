# 0.38.0 operator observability acceptance

Accepted implementation:7e8a092. The final complete gate passed1,032 Lua tests
and23 Python tests. Release generation/check and `git diff --check` passed.
Merging accepted0.37 documentation did not change tested implementation files.

## Automated evidence

Focused runtime, dashboard and production suites passed after the single final
review. Four regressions failed before their corrections: operator overflow during
a yielding command could exhaust a replaced queue and crash; a throttled monitor
attempt cleared a disconnect warning; rapid replacement could leave an identical
page blank; and retired streamed requests retained logging snapshots.

Tests also cover real dispatcher execution through simulated CraftOS coroutine
filters, overflow rejection, command bounds, immutable cached dashboard projections,
monitor dimensions/paging, structured JSON parsing/rotation, post-checkpoint events,
duplicate receipts, failed persistence and logging-disk failures. Drawing does not
refresh physical inventories. Logging failure does not unwind committed ownership.

## Native Minecraft — 2026-10-04

PrismLauncher1.20.1, TESTINMG, Forge47.4.10, CC:Tweaked1.120.0,
Advanced Peripherals0.7.48r. Controller265, builder266 and Crafty267 used ordinary
wired stock, supply/input/output chests, a furnace and an advanced monitor near
(2700,300,0). Workers started with5000 finite fuel; telemetry used shipped
5-second heartbeat,15-second registration and30-second timeout settings. The rig
was supplied with4 cobblestone,2 coal and1 sand, then requested two stone bricks
and one glass. No finished building materials were injected.

The first implementation47ae9a1 built and verified3/3 blocks at(2720..2722,300,0).
An independent command computer confirmed both bricks and the glass, with exactly
2 surplus bricks in stock and empty supply, furnace and crafting inventories.
All production/return requests finished; both workers settled idle and empty.
Builder fuel ended4794; the stationary Crafty retained5000. A controller restart
was exercised before final settlement. The first audit independently parsed148
JSONL records spanning12 event types, including assignment, requirement, measured
delivery, stock ownership, production/project state and role changes.

Keyboard paste, backspace, Enter, monitor touch and correlated local script events
went through the normal runtime event collector and dispatcher. Injection receipts
prove native inventory calls were suspended when commands arrived. Correct-key
import and start commands began approximately199ms and200ms after queueing. The
harness records calls/results and observes state; it does not call app:event or
app:command directly to execute operator commands.

Fixture corrections were explicit: CraftOS uses Enter257/backspace259, whereas the
first harness attempted28; the Crafty's wireless upgrade hid the initially chosen
wired-modem side, so a back modem was connected; its omitted depot setting was
added before final settlement. These were setup corrections, not autonomous
recovery claims. The monitor disconnect-warning defect was observed natively and
fixed with the review regressions.

Final source7e8a092 was installed after settlement with state/settings preserved.
A one-shot harness hook injected140 characters while the real `resources` command
was entering its native stock `list()` call, with two local commands already queued.
The running command succeeded once in54ms; each queued command received one
explicit overflow rejection and was not executed. The collector reported142
discarded entries, no network drops and zero residual backlog. Enter cleared the
discard state; a fresh pasted dashboard command and local project status succeeded.
The final count became143 because that recovery Enter also traverses discard mode.

A disconnected monitor retained its visible error through subsequent throttled
draws. Reconnection cleared the error and repainted. An immediate air/replacement
sequence with identical display dimensions also repainted, proven by a newer
native screen-write receipt. Monitor paging was exercised. Multi-block monitors
placed with setblock did not form a larger display in this fixture; changing
monitor dimensions remains automated-test evidence, not a native resize claim.

Computers265–267 were shut down and all6 test force-load tickets removed. The
player was not moved and no backup was made. The rig and finished blocks remain.
Local scripts, raw event logs, command receipts and final snapshots are ignored
under dist/live-observability/. The sustained16-worker load test and final combined
unassisted build remain later acceptance work.
