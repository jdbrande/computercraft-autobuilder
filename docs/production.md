# Production hardware and recovery

Production plans are stock-aware and dependency ordered. Logs become planks, stairs,
slabs, doors, fences and other registered wood products; furnaces make stone, glass,
ingots and fired clay; the crafting station makes stone bricks, glass panes, iron
bars and other registered products. Recipes target vanilla Minecraft 1.20.1.
Unknown items remain raw acquisition requirements. Mod recipes can be registered
explicitly; there is no guessed recipe or fabricated production success.

## Wired furnace controller

Connect the controller, source storage, and ordinary furnaces to the same wired
modem network. Enable each inventory modem and use its displayed network name.
Configure these settings in `autobuilder/settings.lua`:

```lua
storageInventories = { 'minecraft:chest_0' },
furnaces = { 'minecraft:furnace_0', 'minecraft:furnace_1' },
smeltingFuelItem = 'minecraft:coal',
turtleFuelReserveItems = { ['minecraft:coal'] = 64 },
smeltingWaitSteps = 600,
```

Furnace slots are 1=input, 2=fuel, 3=output. Only ordinary furnace recipes are
registered. The production planner partitions each smelting operation across at most the number
of configured furnaces (and never more lanes than input items). Each durable child
task owns one explicit `furnaceLane`, loads bounded input stacks, feeds fuel, polls
later, and transfers real output back to the first storage inventory. The service
steps these tasks in round-robin order, so several furnaces process asynchronously.
One call to `step()` performs at most one physical mutation. All child tasks must
finish delivering before a dependent crafting operation is scheduled. Duplicate lane
owners block before transfers. A detached or paused lane keeps its ownership. Do not attach hoppers or let players
alter owned furnaces or storage during a transfer/recovery interval. Furnaces must
start with empty input/output. Compatible leftover fuel in slot 2 is permitted.
Residual burn time is not exposed by the generic inventory API and is never counted
as guaranteed available fuel. Coal/charcoal, coal blocks and blaze rods are supported.
The plan rounds fuel separately for each furnace lane and is conservative
about residual burn; unused compatible fuel stays in the furnace. For example, eight
items split across two furnaces require two coal in the plan, even though one furnace
could process all eight with one coal. Reserve shortfalls and this extra lane rounding
are included before acquisition. Plans saved before lane metadata retain their
original single-furnace tranche and fuel budget during upgrade recovery.

The configured turtle reserve stays in source storage. Both planning and execution
exclude it from smelting/crafting consumption. Planning includes any missing reserve
in acquisition needs. Fuel already inside a turtle is independent and is never used
by either production executor. A full output chest, missing input/fuel, detached
peripheral or stalled furnace produces a visible blocked reason. `smeltingWaitSteps`
counts consecutive polls without a successful transfer, not elapsed seconds.

## Local Crafty station

Use a dedicated turtle with the crafting-table upgrade and enough internal fuel to
reach its station. The turtle must be parked at the configured station by the caller;
the crafting executor never moves it. All 16 inventory slots must start empty.
In particular, a scanner in slot 16 or fuel in slot 15 prevents crafting. Minecraft's
Crafty turtle requires slots outside the recipe grid to be empty too. A mining turtle
with carried tools/fuel is not immediately ready for this job. No item is silently
unloaded, consumed as fuel, or discarded to make room.

Place a dedicated input chest immediately above the turtle and a dedicated output
chest immediately below it. Attach both chests and source storage to a wired network
accessible to that turtle (for example, through an adjacent wired modem). The chests
must start empty and must not also appear in `storageInventories`.

```lua
craftingStation = {
  input = 'minecraft:chest_1',
  output = 'minecraft:chest_2',
  inputSide = 'up',
  outputSide = 'down',
},
```

Names must refer to these exact physical adjacent chests. `front`, `up`, and `down`
are supported sides. This station is separate from the miner's above-depot fuel
chest. Source storage must contain the recipe inputs. The controller must grant
exclusive station ownership and prevent another task, hopper, or player from moving
station contents until delivery and reconciliation finish.

For each crafting execution, wired `pushItems` places one ingredient into the empty
input chest; the turtle selects its exact recipe slot and uses `suckUp(1)`. The turtle
grid uses slots 1,2,3 / 5,6,7 / 9,10,11. Once it matches the registered recipe exactly,
the turtle selects empty slot 13 and calls `craft(1)`. The executor checks the entire
resulting inventory against the expected yield, drops bounded output into the lower
chest, and pushes measured quantities back into source storage. It repeats until all
requested recipe executions are delivered. Outputs exceeding one stack are handled
across executions; partial drops and storage transfers remain owned and are retried.
Recipes with returned containers, NBT-dependent ingredients, or unexpected leftovers
are not supported and block for operator review.

The hardware calls follow the official CC:Tweaked
[inventory peripheral API](https://tweaked.cc/generic_peripheral/inventory.html) and
[turtle API](https://tweaked.cc/module/turtle.html#v:craft). Both wired inventory
endpoints must be connected; a wireless modem alone cannot transfer inventory items.

## Lua interfaces

`recipes.get(item)` returns a defensive recipe copy; `recipes.all()` returns the
registry. `recipes.register(item, recipe)` validates and replaces one recipe:

```lua
recipes.register('example:block', {
  kind = 'craft', yield = 4,
  ingredients = { ['minecraft:stone'] = 4 },
  grid = { [1]='minecraft:stone', [2]='minecraft:stone',
           [5]='minecraft:stone', [6]='minecraft:stone' },
})
```

A smelting recipe has `kind='smelt'`, yield 1, exactly one input item and no grid.
Registration does not invent a matching Minecraft recipe: the installed game's
actual recipe must agree. Craft result mismatches are blocked.

`planner.expand(requirements, stock, options)` accepts item-count maps and returns:

| Field | Meaning |
| --- | --- |
| `requirements` | Effective final demands after explicit material substitutions |
| `raw` | Gross raw ingredients reached after allocating finished/intermediate stock |
| `operations` | Dependency-ordered recipe executions |
| `missing` | Additional raw materials, smelting fuel and reserve shortfalls to acquire |
| `reserveMissing` | Reserve shortfall subset of `missing` |
| `available` | Projected unreserved surplus after satisfying demands; projections require acquiring `missing` |
| `fuel` | `item`, `items`, `smelts`, per-item `capacity`, `reserved`, and fuel-only `missing` |

Every operation has `type='CRAFT'` or `'SMELT'`, `item`, `batches` (recipe executions),
`quantity` (full yielded output), and `inputs` (total ingredient counts). `kind` and
`ingredients` are lowercase-kind/input aliases. Each `SMELT` operation also has
`lanes`, an array of `{batches=N, furnaceLane='peripheral-name'}` records, persisted
with the plan. Requests retain their child IDs in `jobIds` until all lanes complete. Finished stock and shared recipe
surplus are consumed before expanding new dependencies. Cycles, malformed counts,
and excessively deep graphs are rejected. `options.recipes` can supply a custom
registry with `get(item)`. `options.substitutions` maps explicitly requested final
items to alternatives; it does not rewrite ingredients inside a recipe. Construction
must apply the same substitutions to its actual block plan. Substitution cycles are
rejected.

`factory.new(task, environment, config, save)` selects the physical executor.
`crafting.new(...)` and `smelting.new(...)` have the same signature. `task` includes
`item` and positive integer `batches`; `quantity` is accepted as a fallback.
`environment` exposes real CC `peripheral` and, for crafting, the local `turtle` API.
`save()` must durably persist the task including its mutable `task.production` state
and return `true` on success. An omitted or failed save never authorizes a hardware
effect. Both `step()` and `resume()` return one of `running`, `waiting`, `blocked`,
`complete`, optionally followed by a reason. The caller schedules subsequent steps,
retains device ownership across disconnection, and releases it after delivery.

## Reboots and uncertainty

Every physical transfer/craft is preceded by a saved intent. Transfers record the
inventory endpoint that does not mutate itself: source storage for furnace loading,
destination storage for furnace output, and both turtle/chest observations for
station suck/drop. Craft intents record the entire expected before/after inventory.
After restart, the executor first compares observations with the saved intent and
credits measured effects once. The bank scheduler reconciles every outstanding lane
intent before allowing another lane to mutate shared storage, including intents on
blocked or paused tasks. If an endpoint is unreadable, all other lane effects wait. A failed result save preserves the original intent
in memory too. Partial transfers are not treated as full batches.

If observed quantities cannot be explained by the recorded operation, the executor
blocks and retains the journal. Preserve the checkpoint and inventories; inspect the
reported discrepancy before an operator repairs the state. Never delete a checkpoint
to retry a possibly completed action. Inventory ownership is essential: no generic
CC inventory API can distinguish a player's identical-item transfer from an owned
transfer across a crash.

The desktop tests simulate real API call shapes, inventory limits, furnace progress,
restart boundaries and failures, including cobblestone-to-stone-bricks end to end.
They are not evidence of a live Minecraft run. Validate peripheral names, station
positions, chunk loading, installed recipes and upgrades in the target world before
large production requests.
