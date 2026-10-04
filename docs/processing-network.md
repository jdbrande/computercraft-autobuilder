# Registered inventory processors

Controllers can register processing inventories and exact recipes. Existing
`furnaces` and normal crafting/smelting recipes retain their current behavior.
A configured process recipe overrides the ordinary recipe for that output.

```lua
processors = {
  machines = {
    {id='blast-a',inventory='minecraft:blast_furnace_0'},
    {id='blast-b',inventory='minecraft:blast_furnace_1'},
  },
  recipes = {
    ['minecraft:iron_ingot'] = {
      yield=1, inputs={['minecraft:raw_iron']={count=1,slot=1}},
      outputSlot=3, seconds=5, machines={'blast-a','blast-b'},
      fuel={item='minecraft:coal',slot=2,batchesPerItem=8},
    },
  },
},
```

Use the actual wired peripheral names and the machine's real slots/recipe. Machines
must expose the ordinary inventory methods, begin empty, and have distinct private
inventories separate from stock, furnaces, crafting, supply and logistics buffers.
Powered modded machines require their power/activation infrastructure to be supplied.
Omit `fuel` for machines that do not consume item fuel. A vanilla stonecutter has no
supported automated inventory contract here; use equivalent crafting recipes.

`request <namespaced-item> <count>` and schematic resource planning use configured
process recipes. `resource <item>` shows the processing provider. Work splits across
compatible machines, with at most64 recipe batches per durable job. Machines stream
one recipe batch at a time and reserve destination capacity before loading inputs.
This supports multi-input recipes and outputs with smaller stack limits without
requiring an entire job to fit in storage at once. Observed output counts, rather
than elapsed time, establish completion.

Ingredient/fuel claims and whole-machine ownership survive restart. Shared storage
transfers use the normal journal and exclusion. Changing a claimed machine or recipe
is refused until its work settles. Paused jobs reconcile already-started transfers,
then retain their claims. Missing power, disconnected inventories, foreign items,
full output storage or incompatible slots report a blocker while preserving ownership.
No guessed replacement batch is issued after an uncertain transfer.

Fuel budgets round independently for each finite machine job. Residual burn energy
is never counted as stock. Unused physical item fuel is measured and returned to
reserved storage capacity before releasing the machine; it is not promised product
output. Recipe inputs, item fuel and output must have distinct item identities and
slots. Container byproducts and machines that internally move items between declared
slots are not this inventory contract and need a dedicated adapter.

`seconds` describes the expected duration; output inspection remains authoritative.
The existing `smeltingWaitSteps` bounds processing wait attempts, with an actionable
power/fuel/recipe/chunk diagnostic. Native chunk loading follows the configured
infrastructure policy; registration does not force-load a machine automatically.
