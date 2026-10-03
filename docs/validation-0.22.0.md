# 0.22.0 worker return and project settlement acceptance

Scope: bounded cargo manifests, journaled home unloading, reserved central collection,
and final project settlement. Full site leveling, dynamic fleet scaling and the other
unfinished fleet requirements remain active subsequent work.

## Automated evidence

Task39 gate:615 Lua and18 Python tests passed. Subsequent regression-backed changes
add project settlement, safe reassignment, pause reconciliation and shared-inventory
exclusion. The pre-review complete branch gate passed622 Lua and18 Python tests; release
generation/check and whitespace validation passed. The single final branch review found two Important settlement races; the fixes
below have regression coverage. Final gate:623 Lua/18 Python tests, release
generation/check and whitespace validation passed. No second review was performed.

Actual controller/worker simulations return mixed cargo, preserve reserved slots,
recover post-drop and post-collection interruptions, retry partial effects and lost
acknowledgements, and prove that central stock is credited only after collection.
Admission tests cover native capacity, disconnected/full inventories, changed cargo
or worker ownership during observation, failed checkpoints and endpoint rebinding.

Project verification now enters settling before built/verified. Runtime tests cover
full return containers, controller/worker restart, lost acknowledgement, subsequent
repair using returned materials, and streamed project retirement. Focused cases retain
production miners after task pruning, wait for production/claims/fresh telemetry,
release empty workers to compatible durable tasks, and propagate project pause even
before a logical return job exists. A paused collection reconciles its already
performed native effect without starting another transfer. Older runtime fixtures
now execute controller work steps and provide actual finite storage and home buffers.

## Native Minecraft — 2026-10-03

Local PrismLauncher1.20.1, TESTINMG, Forge47.4.10, CC:Tweaked1.120.0 and Advanced
Peripherals0.7.48r. Isolated controller170 at `(576,300,0)` and turtle171 initially
at `(584,301,8)`, with home `(584,301,0)`. Central chest800 at `(576,299,0)` and
private return chest801 at `(584,300,0)` share a real wired network. Existing
computers0–9 were untouched. No world backup was made, as authorized.

The worker began with2000 finite fuel, five stone, three dirt, two coal in reserved
slot15 and one diamond pickaxe in reserved slot16. `worker return 171` ran through
the normal controller command boundary. The harness rebooted the worker immediately
after a real dropDown effect and the controller immediately after a real pushItems
effect, before their corresponding software receipts. Saved intents survived both
interruptions; no operator corrected pose, cargo or receipts.

The return settled in13.90 seconds. Independent world NBT reads confirmed exactly
five stone and three dirt in central stock, an empty private chest, and turtle171
at home with1988 fuel. Only the original two coal and diamond pickaxe remained in
its reserved slots. No turtle remained at the original remote position. Final runtime
snapshots recorded completed return/job state and released inventory/capacity claims.

Both computers were shut down. Four explicit fixture loading tickets and the observer
ticket were removed successfully. The rig remains for inspection. Local setup,
continuous observations, cut-point journals, final states, independent world reads,
result and cleanup are under ignored `dist/live-home/`.

A second native trial on the same rig exercised the integrated project gate. The
worker received four stone and `build auto home_project` requested two stone blocks
at `(588..589,300,6)`. Final verification counted two correct blocks, then entered
settling. The controller rebooted during settlement. The project reached built only
after the worker returned and unloaded its two spare stone, in38.48 seconds from
command monitoring. Independent world reads confirmed both placed blocks, central
stock of seven stone plus three dirt, an empty private buffer, and turtle171 home
with1952 fuel and its original reserved coal/pickaxe. No count, capacity or chunk
claims remained held. Both computers were shut down and all five loading tickets
removed again. Additional evidence uses the `project-*` files in the same directory.

Workers used real turtle, peripheral and rednet APIs. Terrain was explicitly operator-loaded,
GPS was disabled with a trusted configured initial pose, and the test did not inject
an ambiguous movement interruption. Movement/GPS recovery has separate0.20 evidence.

## Final review fixes

The single final review found two Important issues, reproduced against the reviewed
commit and fixed in one pass. A completed unrelated task awaiting acknowledgement
could incorrectly qualify as an active reassignment; both reassignment paths now
require physically unfinished ownership. Conversely, a successful home return could
be forgotten when a new task changed the worker's cargo before the project observed
idle telemetry. Matching durable return evidence newer than the actor's last project
work now discharges that actor, including when it later goes offline. Older evidence
creates a new uniquely keyed return request. Regressions cover both races, offline
telemetry and stale proof. Native trials preceded these final admission fixes.

## Limits

Each worker with cargo needs a dedicated registered private buffer at its configured
depot, plus room for its whole finite manifest in that buffer and central stock.
NBT cargo remains held with an actionable error. Configured reserved slots remain
untouched. A full destination can delay that worker while independent returns proceed.
Unclaimed automatic returns can release already-empty workers to compatible durable
work; physically owned returns retain all claims until collection and acknowledgement.
This does not establish arbitrary inventory rescue, automatic infrastructure creation,
full fleet scale-down or large uneven-terrain construction.
