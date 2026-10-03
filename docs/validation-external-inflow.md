# Native external-inflow containment acceptance

Accepted2026-10-03 in the local PrismLauncher1.20.1 instance, world`TESTINMG`,
Forge47.4.10, CC:Tweaked1.120.0 and Advanced Peripherals0.7.48r. Controller210 and
inspection-only builder211 used real turtle, peripheral and rednet APIs. No world
backup was created. The operator supplied infrastructure, terrain, initial stock,
finite fuel and four loaded chunks; the fleet performed all preparation and building.

## Fixture and work

`build auto inflow` requested one glass block at`(1016,300,6)`. The operator placed a
63-block stone floor atY299, an outer stone berm, and a water source at`(1013,300,6)`.
The source lies outside the required workspace and the eventual containment wall.
The source could continuously refill cleared workspace. Central stock started with
one glass and64 cobblestone; the worker started with16,000 fuel and no scanner.

Initial preparation and post-region fluid retries exhausted their bounded budgets.
The controller then scheduled a two-block-high retaining wall outside the required
workspace:32 cobblestone aroundX1014..1018,Z4..8,Y300..301. Four eight-cell placement
jobs were followed by four eight-cell verification jobs. A controller restart during
the second placement batch retained the durable cursor and resumed the same sequence.
No operator placed containment blocks, removed the water source, supplied replacement
materials or modified terrain to finish the trial.

After the wall passed verification, the controller repeated its site census and
preparation checks, built the glass, verified it and settled the worker. All164 jobs
completed. The project reached`built` with one correct structural block, no defects,
no supply/access lease and a verified barrier. The worker returned home at
`(1008,301,0)`, idle with empty cargo and9,482 remaining fuel.

## Independent observations

A separate command computer checked114 world coordinates after settlement:

- All32 wall blocks were exactly cobblestone.
- The18 inner workspace cells contained one glass block and17 air blocks.
- All63 original floor cells remained stone.
- The outside source remained`minecraft:water[level=0]`.

Independent inventory reads found exactly32 cobblestone in central storage, no glass,
and empty private supply/return chests. Native turtle NBT confirmed9,482 fuel. Thus
net fill consumption was exactly the32 permanent wall blocks, with no leftover
preparation cargo. Both test computers were shut down and the four test force-load
tickets removed. The rig, wall, source and completed glass remain for inspection.

## Evidence and limits

Ignored`dist/live-external-inflow/` contains setup commands/responses, deployed files,
passive runtime observations, controller-update records, before/after wall restart
snapshots, final durable state, independent commands/results and cleanup receipts.
The first passive monitor reached its one-hour limit; approximately five minutes
before wall-start sampling were not continuously recorded. Explicit wall-start and
restart snapshots supplement that gap. The harness submits operator commands at the
controller event boundary; this does not test terminal input reliability.

This proves bounded automatic containment for this staged flowing-water envelope,
including a controller restart during wall construction. It does not establish
unbounded fluid containment, arbitrary terrain coverage, a lava inflow trial,
automatic infrastructure deployment or power-loss recovery during an ambiguous
physical move. Separate native reports cover finite lava drainage, multiworker
preparation and hidden-foundation access.
