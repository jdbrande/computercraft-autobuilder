# Autonomous mining candidate validation

Candidate: 0.12.0, `feature/autonomous-exploration`.

## Automated evidence

- Lua suite: 405 tests passed (`.venv/bin/python tests/run.py`).
- Python suite: 16 tests ran, one skipped because the optional local source
  schematic is absent from the isolated checkout.
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

## Live Minecraft acceptance: pending

No live trial or deployment was performed for this candidate. Use the
[operating guide](autonomous-mining.md) and preserve current settings/checkpoints.

- [ ] Keep the whole test envelope loaded and within modem coverage.
- [ ] Configure at least two miners with separate stocked fuel slots, deposit
  inventories included in STOCK, known poses and clear exits beyond protection.
- [ ] Configure a crafting worker, furnace/storage and builder using the existing
  factory and project setup.
- [ ] Import a small supported JSON schematic requiring mineable materials and
  crafted/smelted outputs; run `build auto NAME`.
- [ ] Observe selection beyond an empty first sector and multiple owners sharing
  a material without overlapping territory.
- [ ] Observe partial delivery and continued acquisition of the remaining demand.
- [ ] Pause exploration while miners are away; confirm return/unload and retained
  ownership until reconciliation, then resume.
- [ ] Restart controller and one working miner; confirm recovery and no duplicate
  excavation or delivery credit.
- [ ] Confirm all physical trips reconcile, production completes, and the final
  building verification passes.

Direct binary schematic import, automatic fuel rescue and concurrent factory stock
reservations remain later milestones in the full fleet requirements.
