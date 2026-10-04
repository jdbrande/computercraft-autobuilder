# 0.33.0 deterministic placement adapter validation

Accepted source `abfe12d` passed all **940 Lua tests**, **18 Python tests**,
release generation/check, diff checks and the native acceptance below. Final
source gates completed on 2026-10-04 from a clean candidate checkout.

## Automated evidence

The pre-native-correction gate passed 939 Lua tests. Final-source focused placement
and logistics tests pass. The single final review and consolidated corrections
covered destructive bed repair, ceiling dependency cycles, thin paired blueprints,
paired ownership bounds, one-item bed supply, farmland substrate preservation and
placement capability negotiation. Two subsequent native bugs have regressions:

- A supply ascent could encounter a ceiling beyond the first inspected cell and
  repeatedly reuse its obstructed route. Replan that confirmed initial ascent from
  the actual pose, while preserving reservation waits and ambiguous movements.
- Paired placement recovery stored the same inspection table under two keys.
  CraftOS serialization rejects repeated references. Copy the recovered result;
  test the original task graph before the simulation save deep-copies it. Eight
  existing door/bed cases failed with the strict save before the one-line fix;
  normal placement, interrupted placement, reservation yields and reboot now pass.

The final whole-suite gate includes both native corrections. Logs are retained
locally as `/tmp/fleet-033-final-full-v3.log` and the corresponding Python log.

## Native Minecraft acceptance — 2026-10-03–04

PrismLauncher 1.20.1 `TESTINMG`, Forge 47.4.10, CC:Tweaked 1.120.0 and Advanced
Peripherals 0.7.48r. Controller 244 and builder 245 use a separate rig around
`(1970..2018,300,0..7)`. The builder starts with 20,000 finite fuel. Wired stock,
depot and supply inventories are 1013–1015. Ten chunks were operator force-loaded;
no world backup was created.

The `mixed_adapters` project contains 140 cells: 13 non-air positions and 127 air
positions. It places a north-facing red bed, floor stone button, west-facing wall
lever, ceiling oak button, east-west rail, east-facing repeater, west-facing
comparator, redstone torch, unpowered wire and dandelion, plus two stone supports.
Stock starts with finished placement items, so this run verifies adapters and the
ordinary preparation/supply/build/verify flow rather than raw-resource production.

The controller and worker were paused, allowed to reach settled poses, rebooted
and resumed during placement. The run then exposed the ascent and paired-checkpoint
bugs above. Both corrections were installed and the original task contracts resumed.
The stopped bed worker recovered from its saved checkpoint without replacing the
bed or consuming another item. No ambiguous pose was guessed.

The fixture wiring was corrected before construction. The low ceiling-button
fixture also required two operator-cut floor cells at `(1994,299,7)` and
`(1993,299,7)` to provide underside/side access. This is assisted fixture preparation;
it does not prove automatic preparation of that access geometry. Final integrated
fleet acceptance must independently establish unassisted workspace access.

The project finished `built`, with **140 correct** cells and no defects. Independent
command computer 90 checked every one of those 140 world names/states. All matched.
It also confirmed empty depot/supply chests and an empty builder at its home
`(1974,300,0)`, with 12,348 fuel. Central stock retained exactly one unused item of
each supplied adapter and 14 of the original 16 stone. All jobs completed, the
supply lease settled, and the worker became idle.

Controller 244 and worker 245 were shut down and the ten temporary chunk tickets
removed. The completed structure remains for inspection. Audit records, fixture
scripts, restart snapshots, exact world checks, inventory observations and cleanup
receipts are under ignored `dist/live-placement-adapters/`. Operators submit commands
at the controller event boundary; this is not terminal-input reliability evidence.

The finite supported states remain explicit: no arbitrary redstone circuit behavior,
rail slopes/curves, unsupported plant stages, powered states or unrestricted paired
furniture. The run does not establish automatic chunk loading or larger fleet scale.
