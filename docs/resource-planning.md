# Resource planning and providers

The planner expands a project's recipes into ingredient demand, crafting/smelting
operations and their dependencies. Shared ingredients and batch leftovers are
accounted for once. Existing stock reduces production; fuel held for turtles and
fuel consumed by furnaces are included in demand. Invalid recipes, cycles and
excessive expansion are rejected before scheduling.

On the controller, inspect an item with:

```
resource minecraft:stone_bricks
```

`stock` is the current measured wired inventory total. Each saved request shows
`required` (aggregate demand), `initial` (physical stock at planning time),
`planned` (future output), `deficit` (demand beyond initial stock), `missing`
(unfulfilled raw acquisition), and `provider`. These are request snapshots, not
inventory reservations. Completed request snapshots remain visible. A failed
inventory read reports unknown stock rather than treating stale counts as current.
The production screen also shows the source selected for each acquisition.

Providers derive from registered recipes, mineable materials, `treeFarms` and
`farms`. Their IDs identify the provider type, item, and farm index where relevant.
A configured farm must actually be able to produce its declared item; declaring a
provider does not create terrain, crops, equipment or a machine.

Optional settings select provider types in preference order:

```lua
providerPreferences = {
  ['minecraft:oak_log'] = {'tree_farm'},
  ['minecraft:clay_ball'] = {'farm', 'exploration'},
},
```

Only configure farm sources for items supported by your installed farm adapter.
Supported preference names are `storage`, `exploration`, `mining`, `tree_farm`,
`farm`, `crafting` and `smelting`. Names must be unique within each dense list.
Sufficient physical stock wins first. Otherwise a compatible online source wins
before preferences; missing workers leave a recoverable wait on a configured
source. Unknown sources report an acquisition error. With exploration enabled,
mining candidates use exploration; otherwise they use the configured mining areas.
Preferences select raw acquisition paths; recipe operations keep their registered
crafting or smelting method.

Once a mining job, exploration group or harvest job owns demand, its saved source
and geometry remain authoritative through offline periods, restart and settings
changes. Bringing another provider online never steals that work. Newly unowned
demand can select again. The factory remains exclusive in this milestone; parallel
consumers and durable stock reservations are subsequent work.

The graph is saved with production requests. `plan.graph.nodes[item]` contains
`required`, `available` (initial physical stock), `produced`, `deficit`, `missing`,
`projectRequired`, `inputs`, and provider metadata. Fuel reserves also have a
`reserved` count. Operations have an `id` and dependencies referring to earlier
producer IDs, including producers whose surplus supplied a later operation.
Expected production never increases measured storage or completes acquisition.
