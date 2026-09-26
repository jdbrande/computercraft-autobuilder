# Supply and transport

Configure a dedicated wired staging inventory and its Turtle-facing side:

```lua
supply = {inventory='minecraft:chest_4', side='front', batch=64},
```

The depot coordinate is the Turtle stand position. Set its heading for a front-facing
supply chest. The staging chest should begin empty and stay dedicated to managed
supply. Storage names come from `storageInventories`; the staging inventory is never
used as its own source. `turtleFuelReserveItems` remains in storage, including when
coal is requested as a construction or crafting material.

## Controller staging

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

## Worker resupply

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

## Courier jobs

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
reboots, duplicate grants and lost receipt acknowledgments. A live Minecraft
acceptance run is still needed for peripheral naming, chunk loading
and server protection behavior.
