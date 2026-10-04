# Registered processor candidate validation

Candidate0.31.0, final implementation `677ea67`. Full Lua gate is running; the
fleet roadmap remains unfinished. Focused processor/planner/production/coordination/
forecast tests pass, all18 Python tests pass, release generation/check and diff
checks pass. Accepted0.29 and candidate0.30 evidence merged with source unchanged.

## Automated and review evidence

Tests execute the actual production service and machine transfer journals with
simulated ordinary inventories. They cover multi-input higher-yield recipes,
concurrent machines, partial transfers, startup claim failure, pauses during
capacity observations, transfer/release crashes, disconnected/contaminated hardware,
missing power, saved recipe identity, unused-fuel refunds and exact lease settlement.

The single final review found four Important issues and one Minor imbalance:

- Streamed batches incorrectly relied on residual burn preserving nominal fuel
  efficiency. A regression expires burn between outputs and restarts both owners.
  Planning now reserves one fresh item per batch; observed consumption may be lower.
- Externally satisfied demand left never-assigned acquisition jobs dispatchable.
  Retirement now checkpoints cancellation before input consumption, only when the
  request uniquely owns unstarted demand without telemetry/physical/ledger owners.
  Mining/harvesting, failed retirement and other-consumer retention are covered.
- Batch output could not use combined space across registered inventories. Capacity
  is now claimed atomically across destinations, with partial cross-chest delivery
  and after-effect restart coverage.
- A high-yield first product could not establish its own stack-limit sample.
  Recipes may declare the real `outputStackLimit`; measured samples take precedence,
  collection checks actual limits, and unknown-bound shortages explain the remedy.
- Multi-wave jobs were uneven. Per-machine quotas now balance before64-batch splits.

Repeated interruptions can still exhaust the finite fuel budget; tests require an
explicit blocker and retained inputs rather than invented output or unbounded fuel
withdrawals. Logs: `/tmp/fleet-031-review-red.log`, `acquisition-red.log`, and
`/tmp/fleet-031-consolidated-green.log` (the second red log shares that prefix).

## Native Minecraft acceptance — 2026-10-03

PrismLauncher1.20.1 world `TESTINMG`, wired rig around `(1800,300,0)`, two real blast
furnaces and one smoker. Initial controller239 used actual generic inventory APIs
and produced4 iron ingots and2 cooked beef. Its larger restart test exposed the
fuel defect: one furnace retained one raw iron with no burn or item fuel, after
9/10 outputs and both budgeted coal. The other furnace completed10. Independent
block data confirmed the stall. During staging, the operator had overwritten the
first4 ingots with raw stock; additional raw ingredients corrected that test setup.
No finished output was supplied. The failed candidate was paused and its state/world
receipts retained before resetting this separate test rig.

Final source ran on controller240 with20 raw iron,2 raw beef and22 finite coal.
Both blast furnaces held active work when the controller rebooted. The resumed jobs
produced10 ingots each. The smoker then produced2 cooked beef. All three jobs and
both requests completed, every stock/capacity lease released, and no mining jobs
were queued. Independent world reads confirmed20 iron,2 cooked beef and16 coal in
stock, with all three machines empty. Their native recipe counters confirmed
10+10 blasting operations and2 smoking operations. Measured consumption was6 coal;
unspent fuel stayed in stock or returned through the measured refund path.

Controller239 was shut down before the reset;240 was shut down after acceptance.
Both temporary force-load tickets were removed, confirmed by the command computer.
The player was not moved and no world backup was made. Local audit scripts,
pre-fix failures and final evidence are under ignored `dist/live-processing/`;
`final-source/` contains overlap/restart snapshots, accounting, independent counts
and cleanup receipts. This is native processing acceptance with staged raw inputs,
not a new claim of autonomous ore/food acquisition or a full schematic build.

## Limits

Registered machines must expose ordinary inventory methods with stable declared
input/output slots. External energy and chunk-loading infrastructure must exist.
Container byproducts, internal slot migration and inventory-less stonecutters need
separate adapters. Incorrect recipe/stack declarations report blockers rather than
proving an arbitrary modded machine safe. Native acceptance covers blast furnaces
and a smoker; custom multi-input recipes and smaller stacks are simulation-tested.
