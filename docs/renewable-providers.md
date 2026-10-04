# Renewable providers and planting reserves

Managed plots use the existing `FARM`/`HARVEST` actor, movement permissions,
harvest/replant/deposit journals and demand scheduler. Crop definitions include
wheat, carrots, potatoes and beetroot; beetroot matures at age3 and the other crops
at age7. Simple oak/birch/spruce trunks and bamboo/cactus/sugar-cane columns retain
their existing policies. Branching trees are refused; columns keep their base and
only declared tree leaves within the managed column may be removed.

```lua
farms = {{
  kind='carrot', item='minecraft:carrot',
  sites={{x=12,y=64,z=4},{x=14,y=64,z=4}},
  maxHeight=2, seedReserve=2,
}},
```

Sites name the crop/base blocks; farmland must be below crop plots and ordinary
soil below tree planting sites. Keep clear overhead travel corridors and a depot
with a connected return chest below it. Planting items must already exist or be
available through the normal supply flow. The actor refuses destructive harvest
without a replanting item, replants before leaving a site, and retains one planting
item per configured site by default. An explicit `seedReserve` may raise that count
up to256. This is a retained worker reserve, separate from turtle fuel slots.

For carrots/potatoes, the harvested output is also the planting item. Quotas and
project held-material forecasts exclude retained planting reserves. Only actual
surplus deposited at the depot satisfies material demand. Random drop yields may
overshoot a requested amount; every delivered item remains measured. Initial
planting stock, planted crops, retained reserve and stored surplus are distinct.

Register additional plain crop/column definitions without changing the scheduler:

```lua
farmAdapters = {
  modded_reed={mode='column',block='example:reed',item='example:reed'},
  modded_crop={mode='crop',block='example:crop',item='example:fruit',
    seed='example:seed',age=4},
},
```

Custom crops must use a numeric `age` state and normal planting on farmland;
columns preserve their base and use the existing bounded top-down harvest. The
adapter is copied into its durable farm job, so later registry edits cannot change
an owned action or restart journal. Definitions contain data, never executable
callbacks. Other hardware behaviors require a new supported actor contract.

New crop, custom adapter and explicit-reserve jobs require updated workers advertising
`registeredFarmingV1`/`registeredLoggingV1`. Older workers can still receive compatible
legacy plots. Known broken hardware/software is excluded when selecting an unowned
provider, while active/offline owners keep their work.

Automatic wool/mob/generator infrastructure can expose collected items through the
existing registered storage/logistics contracts. Those observations represent real
items already collected by that infrastructure; they do not implement turtle
shearing, mob handling or arbitrary machine activation. Avoid independent writers
to an inventory while its transfer journal owns it. Processing inventories use the
[registered processor contract](processing-network.md).
