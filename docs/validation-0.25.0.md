# 0.25.0 mining intelligence validation

Status: native acceptance and complete automated gates passed; integration awaits accepted 0.24.
Implementation candidate: `b369e3e`, based on the ongoing 0.24 scaling branch.

## Automated evidence

Focused exploration, miner, protocol, jobs and mining-runtime tests pass. Both
inspection-only and scanner autonomous-chain simulations preserve observations,
confirmed travel and exact physical delivery totals across controller/worker
restarts. The single final review and consolidated fix pass are complete.
The final Python suite passed all 18 tests; release and whitespace checks passed.
The complete Lua suite passed all **802 tests** on `b369e3e`
(`/tmp/fleet-025-final-full.log`).

Review regressions reproduce and correct three errors: transient turtles recorded
as permanent hazards, long clear returns evicting unresolved hazards, and cargo
already carried at the depot falsely increasing learned mining yield. Tests cover
both sensing modes, a 70-cell hazardous trip and its next route, initial-unload
journal recovery, malformed or regressing counters, and conservative legacy data.

## Native Minecraft acceptance — 2026-10-03

The local PrismLauncher 1.20.1 `TESTINMG` world used Forge 47.4.10,
CC:Tweaked 1.120.0 and Advanced Peripherals 0.7.48r. Controller 219 and
inspection-only miner 220 operated around `(1200, 300, 0)` with a wired deposit
chest, diamond pickaxe, wireless modem and 2,000 finite starting fuel. The operator
loaded eight chunks and staged resources and a protected obstacle. No backup was
created. The worker used real turtle, peripheral and rednet APIs.

The initial bedrock at `(1202, 300, 0)` sealed the fixture's only exit. The miner
reported the exact protected obstruction and returned. The operator corrected the
fixture by moving that bedrock to `(1204, 300, 0)` and explicitly retrying its
unowned sector; no building resources were added in that correction. The miner
retained the subsequent obstacle evidence and automatically routed through `z=1`
to the next sector, delivering four requested cobblestone from staged stone.

After both computers restarted at idle, sector diagnostics retained the history.
Increasing the request to six caused another trip to the useful sector and two
additional deposits. Independent world inspection confirmed six cobblestone in
the chest, all six source blocks removed, preserved bedrock, empty turtle cargo
and 1,932 fuel. All acquisition groups completed and the miner returned home.

### Review regression extension

Both computers received `b369e3e`. The operator preloaded exactly one cobblestone
in the miner and increased demand to seven. It unloaded without leaving the depot.
Total receipts increased, but the unvisited sector gained no mined yield. Earlier
reports without initial-cargo attribution remain conservatively unclassified.

The operator then staged two more stone blocks at `(1216..1217, 300, 0)` and an
empty stationary turtle at `(1203, 300, 0)`, and increased demand to nine. The miner
waited for the physical turtle without adding a turtle hazard or exhausting its
sector. An explicit sector retry correctly refused active ownership. A controller
restart preserved the assignment. Removing only the temporary obstruction allowed
the miner to resume automatically, without a resume command. It finished searching
the old sector, selected the next sector and mined both new stone blocks.

Final independent inspection confirmed nine cobblestone in storage: eight actually
mined and one explicitly preloaded test item. The new sector recorded two mined
items and one successful trip; the preloaded item did not count as mining yield.
All eight source coordinates were air, bedrock remained intact, cargo was empty,
and the miner was home with 1,846 fuel. All acquisition groups completed and no
persistent evidence named a turtle. The computers were shut down and all eight
fixture force-load tickets removed. The rig remains for inspection.

## Evidence and limits

Ignored `dist/live-mining-intelligence/` contains setup commands, state history,
fixture correction, restart/diagnostic evidence, independent world reads and
cleanup receipts. `review-retest/` distinguishes the final-source extension from
the original trial. Controller commands enter the normal event-handler boundary;
this is not a terminal keystroke-reliability acceptance test.

Learning is bounded to 64 evidence cells per trip/sector and remains advisory.
Current ownership, protection, fuel and loaded-area checks retain authority.
Historical clear observations do not authorize blind excavation. Negative evidence
is retained ahead of clear travel; a bounded cache can still evict older negatives
when all 64 entries are negative. Operators can inspect and explicitly retry an
unowned changed sector. The native trial covers staged loaded inspection terrain;
scanner learning is simulation-tested, not claimed as native acceptance here.
