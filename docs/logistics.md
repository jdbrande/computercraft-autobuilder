# Managed physical logistics

A controller can keep registered destination nodes stocked automatically, or accept
an explicit `haul minecraft:stone 32 base site`. `logistics` displays requests,
worker ownership, shortages and errors. Each node's wired stock inventory belongs
to the central storage view. Couriers physically move items between private buffers;
this requires wired observation/staging access to both nodes.

Controller settings example (coordinates name your actual containers and stands):

```lua
storageInventories={'minecraft:chest_1','minecraft:chest_2'},
logistics={batchSize=64,nodes={
  {id='base',inventory='minecraft:chest_1',position={x=0,y=64,z=0},
    buffers={{inventory='minecraft:chest_3',position={x=4,y=65,z=0}},
             {inventory='minecraft:chest_4',position={x=4,y=65,z=4}}}},
  {id='site',inventory='minecraft:chest_2',position={x=32,y=64,z=0},
    buffers={{inventory='minecraft:chest_5',position={x=36,y=65,z=0}},
             {inventory='minecraft:chest_6',position={x=36,y=65,z=4}}},
    targets={['minecraft:stone']=48}}
}}
```

Stock coordinates identify the stock container. Each buffer coordinate is the
**turtle stand immediately above its chest/barrel**, not the container itself.
Private buffers must start empty, belong to the same wired network as the controller,
and stay outside storageInventories. They cannot double as fuel, supply or factory
inventories. Register actual positions; a wired peripheral name does not reveal them.
Node containers, buffer chests, stands and overhead access are protected from mining.
Protect connecting cables and other infrastructure with restrictedAreas.

Workers need `automation={courier=true}`, known poses, a configured depot, finite
fuel sufficient for the trip, wireless communication and loaded terrain. Updated
workers advertise logisticsV1 automatically. Configure actual loaded-area assurances
or stationary chunky anchors as described in [chunk loading](chunk-loading.md).
Loading envelopes include registered stock containers as well as courier routes.

Use multiple buffer pairs and independent travel lanes for parallel haulers. Pickup
selection prefers the chosen worker's nearest free buffer; drop selection prefers
its nearest free destination buffer. Overlapping narrow corridors still use cell
reservations; automatic resolution of every fleet deadlock remains later traffic work.

Automatic targets subtract inbound committed cargo and preserve each source's own
target stock, other reservations and protected turtle fuel. Sources rank by distance,
then node ID. Disconnected unused buffers do not prevent selection of healthy ones.
A missing item creates a normal production request once existing stock owners settle.
Every possible factory output in storageInventories must have a registered logistics
node before automatic production; status names any missing registration. Produced
stock waits for the production request's durable completion.
Manual hauls keep their selected source and report its shortage rather than silently
changing nodes. Batches shrink to measured stack and concrete destination capacity.

A batch reserves source quantities, both private buffers and final destination slots
before staging or travel. Shared legacy consumers and fuel staging wait while those
stocks are owned. Several couriers can operate concurrently on independent private
buffers. A worker's final drop enters collecting; the controller measures transfer
into final stock before releasing count, capacity, worker and loading ownership.

Restarts and duplicate messages preserve cumulative receipts. A full destination
buffer retries at heartbeat intervals. Disconnected wired collection retries when
it becomes accessible again. Foreign contents or ambiguous journal deltas retain
ownership and report an error; never clear journals to make them disappear. Offline
workers keep their claims. Active endpoint coordinates/names cannot be changed or
removed through configuration, though target quantities may be adjusted.

Limits:64 nodes,8 buffers per node,64 target item types per node, targets1..1000000,
and batches1..64 further bounded by native stack/capacity measurements. Aggregate
production requests above1000000 report a finite-request error. Shared inventory
isolation still limits cross-role throughput. Broader project supply forecasting,
worker scaling, global traffic recovery and final home return remain required work.

## Existing builder supply and legacy transport

Configure a dedicated wired staging inventory and its Turtle-facing side:

```lua
supply = {inventory='minecraft:chest_4', side='front', batch=64},
```

The depot coordinate is the Turtle stand position. Set its heading for a front-facing
supply chest. The staging chest should begin empty and stay dedicated to managed
supply. Storage names come from `storageInventories`; the staging inventory is never
used as its own source. `turtleFuelReserveItems` remains in storage, including when
coal is requested as a construction or crafting material.

### Controller staging

`Supply.new(queue.state, config, environment, save)` uses `environment.peripheral`.
`offer(batchId, owner, item, count)` returns the granted count or nil/error. A grant is
at most `config.supply.batch` and can be smaller when stock or staging capacity is
limited. Empty stock does not fabricate a grant. `release(batchId)` returns true only
when that batch owns the stage and its chest has emptied (or no owner exists).

The persistent `state.supply` record owns the staging chest across restarts. Another
job/worker/item cannot take it over. Unowned contents, NBT-bearing items and foreign
contents are refused. Every wired transfer records source slot count, stage count
and limit before calling `pushItems`. Recovery requires the observed source loss to
match the stage gain. A partial physical transfer is credited by its actual amount.

Once offered, repeated `offer` calls return the original grant amount, including
after a partial or complete worker pull. They do not refill it. This makes duplicate
grants stable. Each request has a durable identity such as `task:7:3:supply:2`. Release only on
the owning worker's matching supply-completion message; the next request uses a
new batch identity. Completed batch IDs are retained durably alongside owner
release, so delayed task progress cannot refill an already released batch.
The controller acknowledges receipts with `task_supply_ack`.
The worker persists pending receipts outside its current task and retries after a
reboot or task completion until acknowledged. A receipt ID persisted before pulling
closes the crash window between final transfer accounting and receipt promotion.

### Worker resupply

`Resupply.new(task, environment, config, navigation, save):step()` returns true only
when resupply is complete. Otherwise it returns false/error. `resupply in progress`
is a normal partial-pull result; `waiting for supply grant` and
`movement reservation pending` are transient waits.

The caller creates `task.supplyRequest={id=...,item=...,count=...,granted=false}`. A validated
controller grant for that same batch identity sets `granted=true` and `amount`. The amount must be positive, no
more than 64 and no greater than the original request. Completion writes
`task.lastSupply={item=...,count=...}`, then clears `supplyRequest` and `resupply`.
The owning task's `phase` and `position` remain unchanged, allowing its executor to
resume the construction/repair work.

The Turtle follows a persisted overhead route to the depot, faces its heading and
inspects an actual chest/trapped chest/barrel before pulling. Route stages survive
reservation waits without repeatedly increasing the travel height. An empty item
slot first receives one item; subsequent pulls use its reported stack space. Fuel
and scanner slots 15/16 and configured reserved slots are excluded. Full inventories
block without discarding contents. The module does not automatically burn cargo as
fuel; navigation enforces the existing return-fuel reserve.

Each pull records the complete inventory before mutation. Recovery measures the
selected-slot increase and rejects changes to other slots or an unexpected item.
Foreign material is retained with its unresolved intent for inspection. No items
are dropped into the world.

### Legacy courier jobs

`Courier.new(task, environment, config, navigation, save)` exposes `step()` and
`resume()`. A job supplies `source`, `destination`, `item`, and positive `quantity`.
Source/destination are Turtle stand coordinates **above** their respective chests.
Use a dedicated source chest containing the requested item; the Turtle API cannot
select an arbitrary chest slot by item name.

The courier reserves one empty nonreserved Turtle slot, loads a bounded stack,
travels overhead, and deposits downward into an inspected container. Larger
quantities use repeated trips. Other held inventory is left alone. `phase` follows
`setup/work/blocked/completed`; `progress` equals the observed `delivered` count.
A full destination blocks while retaining cargo; after space is available, `resume`
continues delivery. A missing chest never causes a world drop.

`task.cargo` persists route, stage, held amount, slot and the current transfer intent.
A completed pull/drop interrupted by restart is reconciled once from the inventory
delta. Unrelated inventory changes remain ambiguous and block instead of counting
success or repeating the transfer. This accounting assumes exclusive access to the
courier's cargo slot and managed source/destination during transfer.

`tests/logistics_test.lua` provides desktop simulations for exclusive staging,
partial transfers, fuel reserves, interrupted hardware calls, duplicate grants,
reservation waits, foreign cargo, full inventories/chests, multiple trips and resume.
`tests/logistics_runtime_test.lua` also drives real controller/worker runtimes through
build shortages, wired staging, movement reservations, placement, courier commands,
reboots, duplicate grants and lost receipt acknowledgments. The0.12 native construction acceptance covers builder resupply; the0.19
acceptance exercises the managed node routing described above. Server protection
plugins beyond this local instance remain environment-specific.
