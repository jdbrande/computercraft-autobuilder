# Construction executors

`builder.new(task, environment, config, navigation, save)`,
`verification.new(...)`, and `repair.new(...)` expose `step()` and `resume()`.
The environment supplies `turtle`; navigation supplies a trusted `pose`, `goTo`
and `face`. `save()` must durably save task and pose and return true, or false
plus an error. A failed checkpoint stops that executor instance before another
physical operation.

Tasks contain an ordered `blocks` array of absolute `{x,y,z,name,state}` records
(maximum 4096 locally; network batches may be smaller). The caller orders dependencies
and reserves the region plus access corridors. Steps perform bounded travel and at
most one place or dig. The turtle climbs two blocks above the highest target before
horizontal travel and tries four bounded side approaches if descent is obstructed.
It never excavates a route. Enclosed cells can remain inaccessible.

Persisted fields are `phase` (`setup`, `work`, `blocked`, `completed`), `index`,
`progress`, `delivered` (same as progress), `attempts`, `intent`, and `report`.
Progress normally counts cells inspected as correct. When the caller explicitly sets
`task.deferConnections=true`, it also counts physically placed connected cells whose
final connections remain `pending` in the report. A successful Turtle API return
alone never proves placement. `step()` returns true on progress or
completion and false/error when blocked. `resume()` clears a block without resetting
the durable three-attempt limit per placement or removal.

A shortage exposes `missingItem` and `missingCount=1`, so a controller can resupply
and resume. Reserved fuel/scanner slots (15/16 by default) never satisfy build
requirements. Repair requires a free nonreserved slot before digging. It also checks
replacement inventory before removing an existing block. An external supply adapter
is not required by these executors.

## Multiple worker depots

Register each builder's wired supply chest on the controller:

```lua
supplyStations = {
  { workerId=181, inventory="minecraft:chest_903", side="front",
    position={x=640,y=301,z=0,heading="north"} },
  { workerId=183, inventory="minecraft:chest_904", side="front",
    position={x=656,y=301,z=0,heading="north"} },
}
```

Each worker configures the same `depot` position/heading and its own
`supply={inventory="minecraft:chest_903",side="front"}` (use that worker's actual
wired name). Separate registered home-return buffers collect debris. Supply chests
must not alias stock, furnace, fuel, crafting or return inventories. Registered
stations take priority; workers without one use the legacy `supply.inventory`.
Both controller and workers must run the version advertising `supplyStationV1`.

A supply batch retains its endpoint across restart. Drain an owned batch before
changing its station configuration. The controller serializes staging through the
existing supply lease; workers can prepare/build concurrently after collection.
Confirmed traffic conflicts use bounded reserved detours. An occupied destination
or a route outside the search/coverage/fuel limits remains a visible wait.

## Supported placement

`blockstates.classify(name,state)` returns a status and optional explanation.
`placement.plan(block)` returns `stand`, `direction`, `heading`, `item`, and optional
support requirements; unsupported blocks return nil and an explanation.

| Family | Status and limits |
| --- | --- |
| Explicit vanilla cubes | Supported; stone families, wood planks, wool, concrete, glass, terracotta and common solid construction blocks |
| Air | Supported as an empty target; ordinary build never clears occupied air cells |
| Logs/wood/stems | Partial; axes x/y/z, with an accessible solid support face |
| Sand/red sand/gravel/concrete powder | Partial; solid base required |
| Slabs | Partial; dry single top/bottom slabs, support above top or below bottom |
| Stairs | Partial; dry straight top/bottom stairs with explicit heading and support |
| Torches/soul torches | Partial; floor or wall support, wall block IDs map to torch items |
| Wooden and iron doors | Partial; explicit facing/half, left hinge, closed and unpowered; solid floor, both cells empty and lateral hinge cells clear |
| Colored carpets and moss carpet | Partial; solid supporting block below |
| Glass panes, colored panes, iron bars, wood/nether brick fences | Partial; dry, solid base; connections verified after neighboring task cells are placed |
| Lanterns and soul lanterns | Partial; dry, solid base for standing or ceiling support for hanging |
| Ladders | Partial; dry, explicit facing, solid backing block |
| Waterlogged, double slabs, connected stairs | Unsupported |
| Right-hinged/open/powered doors, trapdoors, beds, rails, walls, chests/barrels | Unsupported by this executor |
| Fluids, other block entities, unrecognized blocks/properties | Unsupported |
| Bedrock, command blocks and other unobtainable special blocks | Special acquisition; cannot be placed by this executor |

The registry targets Minecraft 1.20.1. Partial support means the strategy has
additional access/support constraints, checked before consuming inventory. Support
inspection temporarily enters the empty target cell. A solid cube or log face is
required; uncertain support shapes block visibly. Stair neighbors can change shape
later, so run final project verification after all regions finish.

Placement choices follow CC:Tweaked's [1.20 Turtle placement implementation](https://github.com/cc-tweaked/CC-Tweaked/blob/mc-1.20.x/projects/common/src/main/java/dan200/computercraft/shared/turtle/core/TurtlePlaceCommand.java):
placement can fall back from a remote support face to the turtle itself. Checking
the support avoids relying on that fallback for orientation-sensitive blocks.
The [Turtle API](https://tweaked.cc/module/turtle.html) provides adjacent inspection,
placement and digging. No rotation wrench or command computer is assumed.

Door placement uses a side stand at the lower cell's elevation, leaving the future
upper cell free. The support/hinge inspection temporarily enters both empty cells,
then returns to that side stand before placing. All requested door properties must
be explicit; incomplete states are rejected. One item creates the pair. The generated
upper half is inspected from the side, and both halves must match before the lower
cell is credited. An upper-half task only inspects an existing pair and never places
another door. Existing wrong doors cannot be repaired automatically because digging
one half would also alter another cell. Lateral walls/double-door layouts and right
hinges require a future strategy.

The centered hit and preserved vertical-interaction heading come from the
[CC:Tweaked fake-player implementation](https://github.com/cc-tweaked/CC-Tweaked/blob/mc-1.20.x/projects/common/src/main/java/dan200/computercraft/shared/turtle/core/TurtlePlayer.java).
The isolated left-hinge strategy is an inference from that placement context; observed
door states remain authoritative, and any different hinge/facing/power outcome blocks.

Connected blocks initially report `pending` while their neighbors are being built.
By default the executor re-inspects every deferred cell after the rest of its task,
and only then reports it as correct. This queue and its cursor survive restart.
For regions whose neighbors belong to other tasks, `deferConnections=true` permits
physical task completion while preserving pending entries. Its caller must schedule
whole-project verification after all regions finish and must not present pending
connections as verified. Verification always compares the complete requested states,
even when the flag is present. This also detects neighboring blocks which create an
unexpected connection after an earlier placement.

## Recovery, verification and repair

Every place records the target index, selected item/slot and pre-operation count.
Every repair dig records the inspected old block and inventory snapshot. Reboot
reconciliation inspects the destination and inventory before another operation.
An observed placed block and one consumed item advance once. Door recovery also
requires the expected second half; a missing or mismatched half preserves the intent
and blocks without consuming another door. An empty target with
unchanged inventory allows a bounded retry. A consumed item with no matching block,
changed inventory slot, or otherwise inconsistent evidence blocks as ambiguous.
An interrupted dig is reconciled only when the target and inventory agree with a
completed or unperformed removal. A changed replacement block is never blindly dug.

`task.report.entries` contains index, coordinates, expected/actual block data,
status and optional reason. `task.report.counts` counts `correct`, `missing`,
`wrong`, `unsupported`, `inaccessible`, and construction-only `pending`. A verification task can finish with
nonzero defects; its completion means its report is ready. It does not mean the
structure is correct. Expected state strings and inspected boolean/number values
are compared by their textual values.

Repair replaces only explicitly listed mismatching cells and verifies replacements.
Protected names, restricted target/stand coordinates, unknown blocks and containers
are refused. Site clearing uses repair with `task.type='CLEAR'` or `clearSite=true`,
requires `config.clearSite=true`, and requires every supplied target to be air.
Only those listed cells can be removed; there is no volume expansion or route digging.

`tests/construction_test.lua` and `tests/advanced_placement_test.lua` exercise stateful world mutation, inventory use,
orientation, restricted/protected cells, full and reserved inventories, interrupted
place/dig operations, ambiguous recovery, checkpoint failures, bounded retries,
report categories, paired door recovery, deferred neighbor verification and gated clearing. This is desktop simulation evidence. Live
Minecraft placement, neighbor updates and server/mod protection behavior still need
an in-game acceptance run.
