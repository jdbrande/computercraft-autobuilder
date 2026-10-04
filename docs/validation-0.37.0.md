#0.37.0 inventory geometry validation

Candidate source `90fbba4`; final full Lua gate is running.20 Python tests,
focused geometry/setup/network/runtime integration, release and diff checks pass.
The single final review found an effective-map overflow: inferred registrations
could produce a checkpoint exceeding the explicit512-location limit. A failing
regression now verifies the boundary, unchanged restart, rejection without state
mutation and recovery after correcting the configuration. No second review ran.

## Native Minecraft acceptance —2026-10-04

PrismLauncher1.20.1 `TESTINMG`, Forge47.4.10, CC:Tweaked1.120.0 and Advanced
Peripherals0.7.48r. Controller259, builders260/261, fixed miner262 and Crafty263
used a separate rig around `(2566..2604,300,-12..12)`. Workers began with5,000 finite
fuel; the operator kept six fixture chunks loaded. No world backup was created.

The first configuration deliberately omitted the furnace's spatial registration.
The ordinary mining and automatic construction commands retained their requests
but admitted no destructive task. The controller named `minecraft:furnace_1037`
in its diagnostic. Crafty263 advertised its separate wired input/output names.
After adding the furnace box and rebooting, the existing requests resumed.
Crafty263 remained powered off throughout the protection trial.

A protected preparation project overlapped a furnace casing. A fixed mining
corridor intersected another casing inside a private crafting buffer's registered
box. Actual controller mutation grants rejected both targets by inventory name.
The miner stopped at `(2591,300,-8)`, retaining its original job and denied work
reservation. Controller restart preserved that ownership and all registrations.
Preparation reported bounded failed/skipped work and remained incomplete; this
trial does not claim that its builder retained one unchanged blocked task.

A separate one-block project then reached `built` through normal survey,
preparation, construction, verification and settlement. Its final verification
reported one correct block. Independent command computer90 confirmed the actual
cobblestone at `(2580,300,12)`, the unchanged stone casings at `(2590,300,6)` and
`(2592,300,-8)`, and exactly one original diamond in each of seven protected
inventories: legacy Crafty input/output, private buffer/input/output, furnace and
blast-furnace processor. No sentinel inventory was used as material stock.

The unfinished protected project was paused. Removing its furnace registration
and restarting the controller failed before checkpoint replacement with
`Finish retained work before moving/removing inventoryAreas minecraft:furnace_1037`.
Restoring the saved configuration and powering the controller off/on recovered
its existing geometry and ownership. Final snapshots retain the blocked miner
and a preparation survey owner waiting behind another turtle; this is deliberate
incomplete protected work, not a claim that all jobs or workers drained.

All five computers were then shut down (Crafty263 was already off), and all six
temporary force-load tickets were removed. The independent block and protected
fixture remain. The player was not moved.

The fixture initially had incorrect wired-modem face IDs. They were corrected
before any mining assignment or physical worker action; no material inventory
or runtime checkpoint was synthesized. One inventory exposed through the wrong
face caused an initial unavailable-storage diagnostic, and the ordinary mining
command was resubmitted after wiring was corrected. The final review's512-map
boundary is automated evidence; the native trial uses a small map.

Audit files under ignored `dist/live-inventory-protection/` include missing-location
and protected-denial snapshots, project completion, independent world reads,
rejected configuration error, restored settings, final computer state and cleanup
receipts. The harness submits ordinary commands at the runtime event boundary;
terminal input reliability and sustained contention remain later acceptance work.
