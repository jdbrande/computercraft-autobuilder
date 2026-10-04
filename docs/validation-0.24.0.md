# 0.24.0 dynamic fleet scaling validation

Status: accepted. Final source `cebe08e` passes788 Lua tests,18 Python tests,
release/whitespace checks and native48-block construction/settlement acceptance.

## Automated evidence

Focused allocation, admission, limits, metrics, protocol, traffic and home-return
checks pass. Actual controller/worker runtime scenarios cover late registration,
shared mining demand, multiple clearing/building owners, slow/private supplies,
controller restart and idle drain. The final clean-source gate passed788 Lua tests and18 Python tests. Release
verification and whitespace checks pass on the final implementation.

The complete gate on `da9c0a0` failed1/786 tests: a48-block construction scenario
stalled with46 correct blocks. Its retained job showed a builder physically blocked
by a chest while following a traffic detour. A focused navigation regression
reproduced the terminal error. Detours now retain inspected physical obstructions
as bounded path evidence and replan without digging. The regression passes across
reboot, and an opposing two-worker runtime with chests in both side routes passes.
The full gate restarted on `cebe08e`; the failed run is not waived as flaky.

The single final review and consolidated review fixes are complete. Later genuine
runtime findings were fixed with regressions: idle workers obstructing a destination
now receive normal managed home return; preparation-region denials are recognized
as traffic; opposing workers first try their own right to avoid symmetric deadlock;
network draining is bounded to eight packets or250ms between complete handlers.
A21-message burst test covers backlog rescheduling without changing atomic handler
semantics. Detours retain the256-node and16-obstacle limits and existing fuel,
protection, ownership and loaded-coverage checks.

## Native acceptance — 2026-10-03

PrismLauncher1.20.1 world `TESTINMG` uses Forge47.4.10, CC:Tweaked1.120.0 and
Advanced Peripherals0.7.48r. The separate fixture near `(1040,300,0)` contains
controller212, builders213–216 and inspection-only miners217–218. Each worker
started with20,000 finite fuel, a diamond pickaxe and wireless modem. Private
supply/home chests and miner deposits connect to wired central storage. The operator
loaded20 chunks, staged stone deposits,16 glass, and a150-cell uneven foundation
with four shallow holes and dirt obstructions. No finished cobblestone or manual
worker assignment was supplied; no backup was created.

Only builder213 and miner217 initially ran. Additional builders and miner218 joined
after initial owned survey/mining work. Recorded history proves concurrent peaks
of two miners, four clearers and two builders. Both miners and all four construction
workers participated automatically. Controller and worker restarts preserved active
work. The project reached `built` with48 correct positions and no reported
errors. All six workers returned home empty and idle. Both finite production
requests and both acquisition groups completed; no supply owner, active mining
trip or held inventory lease remained.

Fixture corrections are retained in local audit evidence. Two missing home-area
coverage chunks were added. Replacing a stalled controller removed its wireless
modem, which was restored. Neither correction reset ownership or supplied building
materials. Native CraftOS CPU timeout during a large message drain prompted the
bounded-drain fix above. The current physical-detour update was deployed to all
seven fixture computers and restarted through the existing command audit harness.

Setup, source hashes, registration/restart receipts, state history and participation
extraction are retained under ignored `dist/live-scaling/`. Workers use real turtle,
peripheral and rednet APIs. Operator commands enter the controller event-handler
boundary; this is not a terminal-input reliability test. Independent inspection confirmed32 cobblestone and16 glass structure blocks,
146 original stone plus4 cobblestone foundation cells, and402 clear workspace cells.
Of64 staged stone deposits,40 were mined and24 remained. The40 cobblestone reconcile
as32 structure +4 foundation +4 remaining in miner218's wired deposit chest.
Eight cleared dirt remained in central stock. Private home/supply chests and all
worker inventories were empty. Final fuel for213–218 was18536,18106,19032,18982,
19774 and19868 respectively, independently read from the world.
The rig and finished structure remain for inspection. Cleanup receipts are retained
alongside final snapshots; fixture computers are shut down and20 chunk tickets removed.

## Limits

Targets are estimates; physical ownership, finite fuel, material and station
availability, dependencies, protection, coverage and traffic still decide dispatch.
Automatic turtle manufacturing/deployment is not assumed. This staged loaded trial
must not be presented as arbitrary terrain or natural resource-scale acceptance.

The accelerated1-second heartbeat/3-second registration setup saturated the
controller inbox during the long native run. Durable retries preserved progress
but throughput was poor. The fixture was switched to the shipped5-second heartbeat
and15-second registration defaults through normal checkpoint-preserving reboots.
Ownership/cargo and source code were retained. High-rate message overload remains
a known limitation; this acceptance must not claim sustained1-second fleet traffic.
