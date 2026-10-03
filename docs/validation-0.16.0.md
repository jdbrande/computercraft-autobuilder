# 0.16.0 parallel factory acceptance

Scope: durable native destination capacity, private Crafty station contracts,
finite batch scheduling across multiple workers, controller staging/collection,
measured status and recovery. This is a milestone within the full fleet; it does
not declare cross-role continuous-pipeline completion.

## Automated evidence

Task19 added six capacity regressions; full Lua suite476 passed. Task20 added five
private-station cases; suite481 passed. Task21 exercised two independent Crafty
runtime modules, shared-input splitting, output-capacity refusal, disconnected
stations, one-item transfers, interrupted physical staging/crafting/collection,
lost acknowledgements and older shared-furnace drainage; suite487 passed. Additional
short-stock and measured-status cases pass, including counts for older jobs without
timing fields. Final pre-review gate:489 Lua tests and all16 Python tests passed;
release generation/check and whitespace checks passed. Independent review pending.

A regression reproduced a liveness bug during integration: waiting private batches
were consuming every controller action while an older shared furnace owner needed
to finish. Private staging now yields to the existing owner. Private worker fuel
reserves are also excluded from its buffer view: the controller's central input
claim already protects fuel reserves, so exact staged recipe ingredients remain
usable. Private worker receipts cannot credit central stock.

## Native Minecraft acceptance — 2026-10-03

World `TESTINMG`, PrismLauncher Minecraft1.20.1, Forge47.4.10, CC:Tweaked1.120.0
and Advanced Peripherals0.7.48r. Controller120 and Crafty turtles121/122 occupy a
separate wired rig around `(224..236,299..302,0..2)`. Each turtle has a Crafty
upgrade, advanced wireless modem, adjacent wired modem, private buffer and dedicated
input/output chests. Both started with finite2000 fuel and empty inventories.

The operator supplied64 stone to central storage and issued
`request minecraft:stone_bricks 48`. No stone bricks were supplied. The controller
automatically divided the operation into six finite jobs, staged ingredients,
reserved station/central capacity, assigned both workers and collected output.
The harness observed two Crafty tasks active concurrently, then rebooted the
controller and turtle121 during concurrent production. No task was manually resumed
or reassigned. All six jobs and the request completed in approximately101 seconds.

Independent command-computer world reads found48 stone bricks and16 remaining
stone in shared storage, all six private chests empty, both turtle inventories
empty and both fuel levels unchanged at2000. Count and capacity leases were all
released. Native turtle/peripheral/rednet APIs performed the work; the harness
observed snapshots and submitted operator commands at runtime event boundaries.

Evidence: ignored `dist/live-factory/`, including setup commands, state stream,
reboot event, final snapshots and independent block NBT reads. A follow-up request
raised desired stock to64 bricks. The two workers produced16 more bricks from the
remaining16 stone; independent world inspection confirmed64 total bricks, no stone
and empty turtles. The new `factory` view reports idle stations,64 delivered and
measured rates from the follow-up batches (about0.60 and0.55 items/second).
All three test computers were shut down and the observer/station force-load tickets
removed. The rig remains available for inspection.

## Limits and remaining requirements

Unknown output stack sizes reserve one item per destination slot until a physical
stack exposes its native limit. This conservative first-batch cost was exercised
in the live trial. Default batch size is two recipe executions. Configured larger
batches require sufficient capacity; reservations and ownership never expire merely
because a worker is offline.

Legacy shared-storage consumers still use the existing factory barrier. Continuous
mining/hauling/factory/building overlap, general courier capacity/routing, dynamic
role scaling, automatic terrain preparation, native binary schematic import,
chunk loading and broader recovery remain required subsequent work. The native
trial used operator force loading and clear fixed crafting stations.
