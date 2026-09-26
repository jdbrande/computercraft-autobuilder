# Managed renewable farms

Renewable executors operate only on explicitly configured planting sites and bounded
vertical columns. They do not search for wild trees, clear terrain or build farmland.
Prepare the depot, soil, water, spacing and travel corridor yourself. Equipment must
support the relevant turtle digging and placement operations.

Example local settings:

```lua
farms = {
  {kind='wheat', item='minecraft:wheat', maxHeight=2,
   sites={{x=10,y=64,z=0},{x=12,y=64,z=0}}},
  {kind='sugar_cane', item='minecraft:sugar_cane', maxHeight=4,
   sites={{x=16,y=64,z=0}}},
}
treeFarms = {
  {kind='birch', item='minecraft:birch_log', maxHeight=12,
   sites={{x=24,y=64,z=0}}},
}
```

A site's y coordinate is the crop cell, lowest log or retained column base, not the
soil below it. There must be 1–64 distinct sites. `maxHeight` is 2–32 and defaults to
8. Only cells from site.y through site.y + maxHeight - 1 can be harvested. The optional
absolute `travelHeight` must be at least two blocks above every configured column.
Without it, the executor derives that height. Keep this entire travel route clear;
obstructed navigation blocks the task and does not dig a passage.

The depot coordinate is the turtle stand immediately above a chest or barrel.
Preload seeds/saplings into unreserved slots; supply fuel separately in the configured
fuel slot. Fuel, tool and configured reserved slots are never delivered. Two empty,
unreserved inventory slots are required before each harvest action.

| Kind | Output | Managed behavior |
| --- | --- | --- |
| wheat | minecraft:wheat | Harvest age 7 only; replant with wheat seeds on farmland |
| bamboo | minecraft:bamboo | Harvest above the retained base, top down |
| cactus | minecraft:cactus | Harvest above the retained base, top down |
| sugar_cane | minecraft:sugar_cane | Harvest above the retained base, top down |
| oak, birch, spruce | matching log item | Single-column vertical trunk; replant matching sapling on supported soil |

Trees must fit the configured height. Matching leaves in the trunk column can be
removed for access. Adjacent logs observed during descent cause a visible block for
manual handling. The executor never chases branches. Keep oak and spruce in managed
single-trunk layouts; irregular oak branches and 2×2 spruce are unsupported. Jungle,
acacia, dark oak, mangrove and cherry are explicitly unsupported by this executor,
as are kelp and underwater traversal. It does not guarantee a complete canopy survey
outside its configured columns. Missing saplings are reported, not substituted or
assumed to drop from leaves.

An immature plot is skipped. After available yield is deposited, an unmet task
blocks with `blockedCategory='immature'`; `resume()` starts another bounded pass.
A controller may retry that category periodically after growth. Unsupported blocks,
restricted coordinates, protected blocks, uncertain position, insufficient fuel,
missing planting inventory and full depot storage stop the task visibly. A planting
shortage sets `missingItem` and `missingCount=1`. A partially harvested tree must be
finished/replanted before the task can complete, even if its requested yield was
already delivered during an intermediate unload.

## Durability and progress

`logger.new(task, environment, config, navigation, save)` and
`farmer.new(task, environment, config, navigation, save)` return `step()`/`resume()`
executors. Tasks use `type='HARVEST'` or `'FARM'`, `item`, positive `quantity`, copied
`farm` configuration and `phase='setup'`. Public phases are setup, work, blocked and
completed; internal stages track harvesting, planting and delivery.

Before dig, plant or deposit, the executor saves the target and inventory intent.
After reboot it compares the observed block and inventory with that intent before
retrying. An ambiguous result remains blocked. Failed checkpoints prevent the next
physical mutation. Hardware exceptions preserve the intent for recovery. `progress`
counts collected target output; `delivered` counts only measured item removal into a
confirmed depot container. Surplus seeds are delivered while preserving enough for
each configured site. No drop is attempted over ordinary ground.

Fuel estimates include overhead travel and the return trip. Low fuel and inventory
pressure trigger a depot return before another dig; insufficient fuel for movement
itself remains subject to navigation's reserve checks. No automatic refuel operation
is performed by these executors: the controller/depot must supply/refuel the worker.

The implementation uses standard [CC:Tweaked turtle operations](https://tweaked.cc/module/turtle.html).
Desktop stateful tests cover growth/replanting, multiple plots, retained bases,
restricted harvesting, branch rejection, missing saplings, delivery capacity,
checkpoint failures and restart after dig/place/drop. They do not establish live
Minecraft harvesting rates, leaf decay behavior or modded tree compatibility.
