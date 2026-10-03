# Site preparation development acceptance

Candidate branch: `milestone/0.23.0`. This is intermediate evidence for requirement45,
not acceptance of the complete requirement or the full fleet.

## Automated evidence

The normal construction-gate snapshot passes694 Lua tests and18 Python tests. Later
fill selection and automatic final repair changes pass73 focused cases and34 project
runtime cases, including a restart during automatic repair and a three-round limit
for recurring defects. These changes are checkpointed in `e70f4ae`. Release generation,
artifact verification and whitespace checks pass. A full current-tree run remains
required at final milestone acceptance.

The normal pipeline now surveys and prepares foundations before dependent structure
jobs. Independent verified regions can proceed around blocked regions. Missing region
proof reopens bounded evidence recovery without abandoning physical ownership.
Preparation obtains additional fill through normal acquisition and supply, returns
excavated cargo through managed home collection, and verifies support and clearance.

## Native Minecraft trial — 2026-10-03

Local PrismLauncher1.20.1 world `TESTINMG`, Forge47.4.10, CC:Tweaked1.120.0 and Advanced
Peripherals0.7.48r. Dedicated controller180, builder181 and explorer182. Earlier rigs
and computers0–9 were not modified. The operator force-loaded the small test envelope;
this trial does not establish automatic chunk loading or multiworker scaling.

The project placed three glass blocks at `(650..652,300,6)`. Terrain started uneven:
three missing support cells across two columns, a dirt obstruction above the third,
and existing ground to retain. Stock contained three glass blocks and one cobblestone.
The registered miner could gather cobblestone, with stone deposits beyond an empty
first search sector. Both turtles started with6000 fuel. No materials were supplied
after the project started.

`build auto uneven` surveyed the footprint and workspace, removed two obstructing
dirt blocks, returned that debris, filled three cells with cobblestone, verified the
prepared region and constructed the glass. The extra fill came through automatic
exploration and supply. The final report counted3 correct structure blocks, no defects,
and project status `built`. Both turtles returned idle to their configured depots.
Final independent block commands confirmed:

- Glass at all three requested coordinates.
- Cobblestone at `(650,299,6)`, `(651,298,6)` and `(651,299,6)`.
- Retained dirt foundation at `(652,299,6)` and air at the former hill cell `(652,301,6)`.
- Exactly two dirt in central storage; empty supply, return and mining deposit chests.
- Builder5398 and miner5936 fuel remaining. No outstanding supply lease or acquisition.

The initial trial preserved ownership across a controller reboot during debris return.
The successful trial additionally recovered after a world reload and a builder reboot
following its first fill placement while awaiting mined resupply. These are settled
checkpoint recoveries, not proof of arbitrary ambiguous-motion recovery.

### Findings and corrections

The fixture initially reused one inventory as both shared supply and private return
buffer. Configuration validation correctly rejected it; separate front supply and
below-home return chests corrected the setup.

The first trial chose two returned dirt blocks as fill for three missing cells, then
requested dirt despite having only a cobblestone miner. A failing regression now checks
possible fill volume and provider eligibility during selection. The candidate chooses
replenishable cobblestone. Supply amounts still follow actual inspected shortages.
The failed trial was preserved and the dedicated rig reset for the fresh trial.

The second trial reached the1 MB ComputerCraft disk quota while saving debris-return
state. Existing journals were preserved. The test-world computer quota was raised to
8 MB, activated by a world reload, and work resumed from saved state. This is an explicit
environment requirement for this trial; compact fleet history and disk admission remain
unfinished. No claim is made that this candidate supports growing projects at1 MB.

The installed trial included the fill-selection correction but predates automatic final
repair. Automatic repair has simulation evidence only. Finished glass was supplied in
initial stock; this trial proves preparation and fill acquisition, not manufacture of
the glass. Manufacturing has separate earlier acceptance evidence.

The fleet was shut down and its force-load tickets removed. The rig and finished blocks
remain for inspection. Local setup, failed-trial records, sampled runtime evidence,
final snapshots and independent block/inventory checks are under ignored
`dist/live-site/`.

## Remaining acceptance

Flowing-fluid containment, access to fully sealed foundations, shared protection for
all remaining mutation paths, larger preparation jobs and simultaneous clearing/building
workers remain unfinished. Dynamic worker scaling is separately required by section44.
