# Parallel Crafty stations

Configure multiple private stations to let Crafty turtles work concurrently on a
production operation. Existing `request` and `build auto` commands use them
automatically. A station needs a Crafty upgrade, wireless controller communication,
a wired modem connection, and three distinct wired inventories:

- **Buffer:** controller stages exact ingredients here and later collects output.
- **Input:** adjacent to the turtle on its configured input side.
- **Output:** adjacent on its output side.

For example, input above, output below and a wired modem behind the turtle. The
buffer can be anywhere on the same wired network. Start all three chests and the
turtle inventory empty. Each station has one worker; inventories cannot be shared
with another station, central storage, a furnace, supply staging or a fuel station.

Controller settings (merge into the existing configuration):

```lua
storageInventories = {'minecraft:chest_0'},
craftingBatchSize = 2, -- maximum recipe executions per finite task
craftingStations = {
  {id='west', workerId=12, buffer='minecraft:chest_1',
   input='minecraft:chest_2', output='minecraft:chest_3'},
  {id='east', workerId=13, buffer='minecraft:chest_4',
   input='minecraft:chest_5', output='minecraft:chest_6'},
},
```

Worker12 settings:

```lua
role = 'worker', controllerId = 7,
automation = {crafting=true},
craftingStation = {
  buffer='minecraft:chest_1', input='minecraft:chest_2',
  output='minecraft:chest_3', inputSide='up', outputSide='down',
},
```

Use worker13's corresponding names for the second station. Both workers need known
positions/headings as usual. The station names in controller and worker settings
must match exactly. Reboot after changing settings. `isolatedCraftingV1` is
advertised automatically; older workers remain eligible only for legacy work.
Controller `craftingStation` is the legacy single-station setting; the new list is
`craftingStations`. Leave legacy names empty unless maintaining a separate station.

## Reservations and completion

The controller reserves ingredient counts, exclusive station inventories and
concrete central output slots before moving ingredients. Transfers use measured
native counts and durable journals. Workers access their private buffer only;
central fuel reserves have already been protected by the controller's input claim.

A worker completion receipt means its private output is ready. The job remains
`collecting` and keeps its worker/station ownership until the controller confirms
all output in shared storage and empty private chests. Shared-stock reservations
and expected production are not physical output. Offline workers retain ownership;
duplicate progress and restarts cannot allocate their batch again.

Capacity uses native slot limits and observed item stack limits. An unknown output
is conservatively reserved at one item per slot until that item has been observed
in storage. Two default stone-brick batches yield eight items and require eight
initial output slots; subsequent measured stack limits permit denser reservations.
`craftingBatchSize` (1–64) is a maximum. Production automatically chooses a smaller
batch when native capacity or unreserved ingredients require it. A first pane batch,
for example, produces16 panes rather than trying to reserve32 unknown-stack outputs
in a27-slot chest. Later physical samples can permit larger batches. If even one
recipe cannot fit, the error identifies the inventory; other feasible stations can
continue. Native observations are cached only for that grant and refreshed next time.

An unclaimed station preference holds neither ingredients, worker nor production
coverage. The actual interval, counts, output slots and journals are saved atomically
before staging. Owned contracts never resize. Older production tasks with an input
claim but no capacity, worker or physical journal are durably cancelled and replaced
with fresh task IDs; completed or physically started tasks retain their exact work.
Explicit standalone CRAFT contracts retain their requested quantity.

## Status and recovery

Run `factory` for configured stations, active/queued batches, measured delivered
output, per-station collection rate and the current bottleneck. Shift N/P changes
pages. Rates use completed output divided by the elapsed time from staged readiness
through collection; waiting and recovery during that interval count against the
rate. They are observed throughput, not predicted item availability.

Restore a disconnected inventory, clear its reserved capacity without moving owned
items, or correct the reported physical obstruction. Controller staging/collection
retries safe observations automatically. A blocked worker task can be resumed with
`resume <task-id>`. Reboot retains transfer/craft journals. Never delete a task,
capacity lease or buffer contents to make an error disappear; ambiguous changes
remain owned for explicit reconciliation.

Legacy shared-stock crafting, furnace operations, mining and supply retain their
existing physical barrier. This milestone allows concurrent private crafters;
cross-role continuous production, broader courier routing and dynamic role
allocation remain required work in [fleet progress](fleet-progress.md).

Configuration changes do not release saved station ownership. Startup rejects a
shared storage/furnace/supply/fuel/legacy endpoint that aliases an unfinished
private station, or assigns its inventories to a different station contract.
Restore the previous configuration, let the owned work drain, then reconfigure.
Private operation routing is checkpointed before batch creation and recovered
from existing batches, including older checkpoints without the routing marker.
