# 0.24.0 dynamic fleet scaling validation

Status: final complete test gate and native48-block acceptance still running.
Current implementation: `cebe08e`. This report does not claim release acceptance.

## Automated evidence

Focused allocation, admission, limits, metrics, protocol, traffic and home-return
checks pass. Actual controller/worker runtime scenarios cover late registration,
shared mining demand, multiple clearing/building owners, slow/private supplies,
controller restart and idle drain. Python18, release verification and whitespace
checks passed on the preceding candidate; final source checks remain pending.

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

## Native trial in progress — 2026-10-03

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
work. Final structure, foundation, stock, cargo, fuel and idle/lease reconciliation
remain pending; interim progress is not final acceptance.

Fixture corrections are retained in local audit evidence. Two missing home-area
coverage chunks were added. Replacing a stalled controller removed its wireless
modem, which was restored. Neither correction reset ownership or supplied building
materials. Native CraftOS CPU timeout during a large message drain prompted the
bounded-drain fix above. The current physical-detour update was deployed to all
seven fixture computers and restarted through the existing command audit harness.

Setup, source hashes, registration/restart receipts, state history and participation
extraction are retained under ignored `dist/live-scaling/`. Workers use real turtle,
peripheral and rednet APIs. Operator commands enter the controller event-handler
boundary; this is not a terminal-input reliability test. The rig and its force-load
tickets remain active until completion and independent inspection.

## Limits

Targets are estimates; physical ownership, finite fuel, material and station
availability, dependencies, protection, coverage and traffic still decide dispatch.
Automatic turtle manufacturing/deployment is not assumed. This staged loaded trial
must not be presented as arbitrary terrain or natural resource-scale acceptance.
