# Release 0.12.0 acceptance report

Release: **0.12.0**, tag `v0.12.0`. Accepted on 2026-10-02.

Acceptance scope: autonomous exploration of supported mining materials through
smelting, crafting, construction and verification of a small schematic in a
loaded test envelope. The limitations below remain separate future capabilities.
The two live-test fixes and regressions are committed in `487c1bb`.

## Automated evidence

Final release gate, run from committed, clean `main`:

```sh
.venv/bin/python tests/run.py
.venv/bin/python -m unittest discover -s tests -p 'test_*.py'
python3 tools/release.py --check
git diff --check
git status --porcelain=v1 --untracked-files=all
```

The status check must return no entries. The two pre-existing local HEIC photos
are preserved and excluded by exact filename in `.git/info/exclude`; they are
not release artifacts. Test logs and live audit data remain local under `dist/`.

- Lua suite: 406 tests passed (`.venv/bin/python tests/run.py`).
- Python suite: all 16 tests passed in the main checkout.
- Release generation and `python3 tools/release.py --check` passed.
- `git diff --check` passed.

The full-chain simulations use actual controller, miner, factory and builder
modules with simulated turtle hardware. Four explorers search without configured
deposit coordinates. Two share cobblestone demand, and other explorers find sand
and coal after empty sectors. The factory smelts and crafts the requested blocks;
the builder places and verifies three blocks. Controller and worker restarts are
included. Both scanner and inspection-only versions pass with finite starting
fuel. Tests supply loaded terrain, wired storage, fuel and tools; they do not prove
automatic chunk loading or fuel distribution.

Focused tests cover partial receipts, changed duplicate assignments, paused or
disabled dispatch, journaled excavation, low fuel, waterlogged blocks, obstructed
return, failed ownership checkpoints, project protection and bounded expansion.

The final review identified eight issues. Regression-backed fixes cover malformed
message rejection before deduplication, sectors overlapping another owner's route,
bounded planning across ticks, new setup superseding saved expansion, safe returns
around survey obstacles, registered depot/exit protection, retained coverage after
clipped-sector expansion, and reopening acquisition after live stock disappears.
An additional case checks that an unfueled explorer cannot delay a ready worker.

Active routes and exits remain exclusive until return. This favors simple durable
ownership at the cost of concurrency on shared corridors. Detour planning is
capped at 256 nodes per candidate; intricate routes may be skipped while other
sectors are considered.

## Live Minecraft acceptance — 2026-10-02

Tested in the local PrismLauncher `1.20.1` instance, world `TESTINMG`, with
Forge 47.4.10, CC:Tweaked 1.120.0 and Advanced Peripherals 0.7.48r. The separate
rig is at approximately `(64, 300, 0)`. Existing computers 0–9 were not changed.
No world backup was created, as requested.

The fixture used controller 100, miners 101–104, crafting turtle 105 and builder
106. Each worker started with 2,000 finite fuel. Four miners used inspection-only
exploration with separate depots/exits, two sharing the cobblestone request.
Empty first sectors forced exploration into further sectors. Stock began without
building materials; operator commands placed stone, sand and coal ore deposits.
A wired network connected deposit chests, the crafting station, supply chest and
ordinary furnace. The operator kept the small test envelope force-loaded.

`build auto live_acceptance` requested two stone bricks and one glass block.
The initial acquisition delivered four cobblestone, two coal and one sand.
The furnace produced four stone and one glass; the crafting turtle made four
stone bricks. The builder placed two bricks and the glass at `(70..72, 300, 0)`.
The project reached `built`, with its final VERIFY report counting **3 correct**
blocks and no defects. An independent command computer read the actual world
blocks and confirmed the expected names in all three positions.

Four miners were active concurrently. Both cobblestone miners delivered two items
against the shared four-item demand. The initial twelve trips reconciled:
four paused returns, four exhausted empty sectors and four quota deliveries.
Exploration pause/resume retained survey progress. A controller restart while
miners returned, and miner 101's restart at its depot, preserved ownership and
allowed work to continue. This does not claim recovery from power loss during
an ambiguous physical move.

### Failures found and corrected

- The fixture initially lacked the crafter's wired modem and source-inventory
  configuration, and left coal blocks in its reserved slot. Corrected those
  setup errors; no finished building materials were supplied by the operator.
- A blocked CRAFT task's resume handler performed one factory action but left
  its outer task blocked. Resume now schedules work through the normal action
  loop. A regression reproduces disconnect/reconnect and reboot, checks that
  the control handler does not transfer items, and verifies exact output.
  The same live crafting job then completed.
- Delayed progress following an acknowledged supply delivery could cause the
  controller to request replacement materials for an already released batch.
  The controller now skips the durable completed-batch IDs. The delayed-message
  regression failed before the fix and passes afterward, including a subsequent
  legitimate supply batch. The first live run had already queued one unnecessary
  glass request. Its first coal deposits were exhausted. Extra test ore placed
  during cleanup obstructed a previously cleared return route, so it was removed;
  one raw coal was supplied to finish that pre-fix request and let the fleet drain.
  This operator-assisted cleanup is separate from the initial autonomous build.

With both fixes installed, a second project, `live_supply_retest`, placed and
verified one glass block at `(73, 300, 0)`. The controller retained exactly four
production requests before and after this placement: no replacement request or
new mining trip appeared. Final checks found both projects `built`, all requests
and acquisition groups completed, no active mining trips or supply lease, and
all six workers idle. Independent world inspection confirmed the extra glass.

The test fleet was then shut down, the fixture datapack disabled, test force-load
tickets removed, and the player returned to the original base position. The rig
and four finished blocks remain in the world for inspection.

The test harness observes normal runtime state and submits operator commands;
workers use real turtle, peripheral and rednet APIs. Controller commands are
submitted at its event-handler boundary because immediate synthetic paste/key
pairs can be lost while CraftOS peripheral calls yield. This is not a terminal
input-reliability acceptance test. Local audit records, setup scripts, final
snapshots and test output are under ignored `dist/live-autonomous/`.

The live trial covers inspection-based exploration in a staged, loaded envelope.
Scanner exploration remains simulation-tested. It does not establish arbitrary
terrain coverage, automatic chunk loading, fuel rescue, or large schematic scale.

Direct binary schematic import, automatic fuel rescue and concurrent factory stock
reservations remain later milestones in the full fleet requirements.
