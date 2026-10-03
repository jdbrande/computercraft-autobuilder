# Finite fluid preparation acceptance — 2026-10-03

Intermediate 0.23 evidence for water/lava clearance and reusable sealing material.
This does not complete requirement45 or establish cross-region/external-flow
containment. The candidate includes bounded preparation retries and fluid sealing
after `b3c4774`; the later scanner fallback was not installed for these trials.

## Automated evidence

Executor, geometry and controller tests cover fluid-only sealing, protected fluids,
dry-block preservation, complete sealing before clearing, and durable placement
reconciliation after reboot. Actual controller/worker simulations drain finite water
and lava flows, restart after a physical plug placement, recover the fill and build
two glass with exact dig/place counts. Preparation retries repeat survey and work
under a new epoch at most three times, retaining prior ownership and cargo receipts.
Failed checkpoints and a changed foundation have regression coverage. A final full
current-tree gate remains required before milestone integration.

## Native trial

Local PrismLauncher Minecraft1.20.1, world `TESTINMG`, Forge47.4.10,
CC:Tweaked1.120.0 and Advanced Peripherals0.7.48r. Controller200/builder201
handled water near `(840,300,6)`; controller202/builder203 handled lava near
`(880,300,6)`. Each builder began with8000 finite fuel. Each wired storage network
held two glass and16 cobblestone, with separate front supply and below-home return
chests. The operator built contained basins and placed one source fluid per basin.
The operator force-loaded12 chunks. No backup was created.

Normal `build auto` surveyed each site, detected flowing fluid, temporarily sealed
fluid cells with cobblestone, cleared the solids, returned all fill to storage,
verified preparation, placed two glass and verified construction. Both projects
reached `built`; all jobs completed, supply ownership drained, and both workers
returned empty and idle. Final fuel:201=7416,203=7348.

Independent world commands checked all48 prepared clearance cells: four glass and
44 air, with no remaining fluid or temporary fill. Both central chests again held
exactly16 cobblestone and no glass. All four supply/return chests were empty. Empty
NBT lists return command success-count zero; the harness checked their actual `[]`
payloads rather than interpreting that count as a failed inventory observation.

No runtime bug or material assistance was required during these trials. Restart
recovery is simulation evidence here; no native mid-action restart was injected.
The harness observes runtime state and submits ordinary commands at the event
boundary; workers use actual turtle, peripheral and rednet APIs. The four computers
were shut down and all12 force-load tickets removed. The player was not moved.
Commands, sampled state, final snapshots, all independent cell/inventory observations
and cleanup receipts are under ignored `dist/live-fluid/`.

The basins were contained by operator-supplied walls outside the working margin.
This proves finite pocket drainage within one region, not automatic external-fluid
barriers, cross-region sealing, chunk loading or autonomous acquisition of the
supplied glass/fill. Those capabilities remain separately tracked requirements.

## Two-region water trial

A subsequent controller204/builder205 trial used nine glass targets at
`(920..928,300,6)`, crossing two preparation regions. Its contained basin started
with a water source at the far end,32 cobblestone and nine glass in wired storage,
and12000 finite turtle fuel. The operator force-loaded six chunks. Both regions
surveyed, sealed/cleared where needed and verified; the project finished `built`
with nine correct blocks, no defects, no active jobs/supply and a home-idle worker.

Independent commands verified all66 clearance cells: nine glass and57 air. Central
storage again held exactly32 cobblestone; the supply and return chests were empty.
Final fuel was10676. Both computers were shut down, all six tickets removed, and
pause on focus loss restored. Commands, sampled state, final observations and cleanup
are under ignored `dist/live-cross-fluid/`. Operator-supplied containment remains a
limit; this trial does not prove autonomous external-fluid barriers.

The native run did not exhaust its early-region retries. A separate actual runtime
simulation deliberately delays the source region until the earlier region exhausts
three retries. It then removes the source, restarts both runtimes during the bounded
reconsideration pass and finishes all nine blocks with no supply ownership. Service
tests also prove persistent inflow stops after eight attempts and failed checkpoints
do not reset the pass. This separates real cross-region flow evidence from the
simulation evidence for that specific delayed-source recovery.
