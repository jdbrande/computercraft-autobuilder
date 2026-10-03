# Resource dependency and provider acceptance — 0.13.0

## Scope

Fleet requirements 7–8: bounded aggregated dependency graphs, explicit operation
edges, provider candidates/preferences and durable acquisition selection. The
existing factory barrier remains. This is not acceptance of parallel crafting,
automatic fuel delivery or arbitrary-terrain operation.

Graph tests cover shared intermediate stock and batch surplus, original physical
stock versus planned output, reserve/furnace fuel demand, malformed recipes,
cycles, count bounds and substitutions. Provider tests cover copied configuration,
dense preference validation, online fallback, unknown sources, newly configured
farms and saved offline owners through restart/configuration changes.

Final review found two recoverability defects: never-assigned mining jobs could
block a newly available alternative indefinitely, and exploration workers were
incorrectly treated as eligible for fixed-area mining. Regressions failed before
the fixes. Retirement now checkpoints before replacement, rolls back on save
failure, and retains assigned, paused or telemetry-claimed ownership. Provider
eligibility now matches the legacy dispatch restriction.

## Live Minecraft evidence — 2026-10-02

Reused the 0.12.0 rig in PrismLauncher 1.20.1 / TESTINMG, controller 100, miner 101
and Crafty 105. Miner 102 was powered but had no matching cobblestone demand.
The operator force-loaded the small test envelope and placed four stone blocks
at `(89..92,300,1)`. Initial measured stock was two stone bricks and one coal.

`request minecraft:stone_bricks 6` saved graph demand of six bricks, original
stock two, planned output four, with four cobblestone and one coal as inputs.
Miner 101 delivered four cobblestone; the furnace produced four stone; Crafty
produced four bricks. The request completed with six physical bricks in storage.
No finished materials were added by the operator.

The initial deployment left already loaded controller modules in memory while
the lazy planner loaded new code. A controller reboot loaded all changed modules
and preserved the running request. To verify fresh dispatch through the new
selection path, two more stone blocks were staged at `(93..94,300,1)` and
`request minecraft:cobblestone 2` was submitted after reboot. The request saved
`exploration:minecraft:cobblestone`, assigned miner 101, received two cobblestone,
and completed with the miner home and no active trip. `resource` reported live
stock and saved graph/provider values independently.

An independent command computer inspected the actual depot chest: six stone
bricks and two cobblestone. The active test computers were shut down and the test
force-load tickets removed. Local snapshots, independent inventory reads and
cleanup responses are under ignored `dist/live-resource-planning/`.

This live check covers graph persistence and ordinary exploration dispatch into
physical mining/smelting/crafting. Alternative-provider selection, offline-owner
retention and the final review fixes are simulation-tested. It does not establish
farm geometry validity, native binary schematic import or large fleet scale.

## Known limitations and decisions

- Never expire physical/offline ownership to improve availability. Only queued,
  never-assigned jobs without telemetry claims may change unavailable sources.
- A configured farm must produce its declared item. Registry entries describe
  sources; they do not build farms or bypass executor validation.
- Missing logging/farming workers still show a generic acquisition wait. This
  minor review finding is tracked for the worker-health/status milestone.
- Reservations, concurrent consumers and fuel dependency extensions follow this
  milestone. Existing exclusive factory journals remain authoritative meanwhile.

## Final automated gate

- `.venv/bin/python tests/run.py`: 420 tests passed.
- `.venv/bin/python -m unittest discover -s tests -p 'test_*.py'`: all 16 passed.
- `python3 tools/release.py --version 0.13.0` and `--check`: passed.
- `git diff --check`: passed.

Final logs are archived locally under `dist/release-0.13.0/`.
