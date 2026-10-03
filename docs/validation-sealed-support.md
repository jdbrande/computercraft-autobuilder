# Sealed support scanner acceptance — 2026-10-03

Intermediate 0.23 evidence. Reused the completed water basin from
[finite fluid acceptance](validation-fluid-preparation.md), controller200 and
builder201, in the same Minecraft/Forge/CC:Tweaked/Advanced Peripherals instance.
The operator added a stone layer atY298 beneath the existing Y299 foundation and
supplied one Geo Scanner in reserved slot16. The two finished glass at
`(840..841,300,6)` stayed in place. Six chunks were operator force-loaded.

`build repair water` ran a fresh survey/preparation generation. Ordinary adjacent
inspection could not reach the foundations: glass occupied their upper stands and
stone occupied their sides and lower stands. The optional scanner provided four
fresh positive observations—two during fill evaluation, two during final foundation
verification—identifying stone atY299. The worker retained the glass and stone and
completed the repair/verification pipeline. The project reached `built`, reporting
two correct blocks with no defects; the worker returned idle at its home.

Independent commands confirmed both glass and all60 stone blocks in the two-layer
`(838..843,298..299,4..8)` floor. Native inventory/upgrade reads confirmed the pickaxe
restored on the left, scanner returned to slot16, and no other turtle cargo. Central
stock still held all16 cobblestone. Fuel fell from7416 to6658; exhaustive physical
approach attempts currently cost substantial travel before each fallback scan.

The controller and worker were shut down, all six force-load tickets removed, and
automatic pause on focus loss restored. No backup was created and the player was
not moved by the test harness. Local setup, sampled scan receipts, final state,
independent observations and cleanup receipts are in ignored
`dist/live-sealed-support/`.

Simulation covers both fill and verification, missing/fluid scan results, failed
tool restoration and executor recreation before recovery. Native interrupted swaps
were not injected. Scanner absence does not prove air, and block names cannot prove
exact schematic states. Missing sealed support still requires a safe access/fill
path; this trial proves only existing generic support beneath retained structure.
