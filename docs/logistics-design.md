# Physical logistics and registered nodes

Required by fleet sections12–13 and28; prerequisite for continuous supply,
dynamic hauling and site fill. Implement natively on the existing Lua controller,
queues, count/capacity ledgers and physical courier. No new dependency.

## Contract

`logistics={batchSize=64,nodes={}}`. A node has `id`, `inventory`, `position`
(the stock container), `buffers={{inventory,position}}` (position is the turtle
stand immediately above a private container), and optional `targets={item=count}`.
At most64 nodes and8 buffers per node; batchSize1..64; targets1..1000000.
All node stock inventories must be in storageInventories and distinct. Private
buffers must not alias any stock, supply, fuel, furnace or crafting endpoint.
Coordinates and identities are validated and immutable while owned. Missing or
rebound live endpoints refuse startup. Nodes/stands are automatically protected;
additional cables and infrastructure use existing restrictedAreas.

A haul request names item, quantity and two registered nodes. Automatic restocking
chooses an available source by distance then identity, subtracts existing inbound
work, and schedules finite batches until each target is satisfied. If registered
stock is insufficient it uses the existing production request graph. Manual haul
keeps its explicitly chosen source and reports shortages there.

Each batch selects one exclusive empty source buffer and destination buffer,
reserves the exact source count and concrete final destination slots, then stages
only its item into the pickup buffer. Turtle suction cannot select a mixed chest
slot, so private staging is necessary. Several buffer pairs allow concurrent
haulers; one buffer pair stays owned through collection. Native measured stack
limits and destination capacity bound batch size. No trip is assigned before
staging and all claims are durable. Source and final stock remain wired-observed;
unwired inventory discovery is not claimed.

The immutable managed transport contract contains the node and buffer snapshots.
New couriers advertise logisticsV1. Worker pickup/drop use existing physical-action
journals plus cumulative pickup and delivery counters. Acknowledged worker completion
enters collecting; only exact drop-buffer to destination-stock transfer credits a
central delivery and releases count/capacity/worker/chunk ownership. Duplicate
messages cannot credit stock. Offline owners retain all claims. Changed contracts,
foreign contents, full or disconnected destinations stop with actionable errors.

## Integration and recovery

Reuse journaled factory transfers for staging/collection, under the production
inventory observation/action lock. Reconcile pending journals before other shared
transfers. Count claims reserve inputs and outputs of the same item; measured staging
withdrawals become transit until final collection. Worker counters do not credit
central stock. Claims and immutable endpoint snapshots survive all restarts.

Existing shared-consumer isolation remains while a batch owns source stock. Permit
older active factory work to drain before acquiring a haul; an unclaimed haul must
not prevent the factory producing its missing input. Multiple managed couriers may
move concurrently using private buffers and existing cell/chunk/fuel admission.
Automatic retries resume only recoverable full/disconnected endpoints with unchanged
journals; ambiguous physical edits retain ownership and report exact cause.

Alternative direct suction from mixed stock cannot guarantee item selection;
alternative generic remote storage service adds a new protocol without required
hardware. Reusing private buffers and existing ledgers is the smallest safe path.

## Acceptance

Simulation: alias/coordinate/target validation; config changes with held jobs;
double spending source count and final capacity; partial effects; stage, suck, drop
and collection after-effect restart; stale receipts; offline owners; two parallel
haulers; capacity-based finite sizing; automatic restocking and production shortage;
active factory drainage; loaded infrastructure and global protection.

Native: two couriers with finite fuel, mixed initial stock, private endpoints and
exact final counts; controller/worker restarts and a temporarily unavailable endpoint.
Independently inspect inventories and all outstanding claims. Record actual hardware
limits and evidence. Later milestones remove broader cross-role barriers, add early
builder/fuel routing and final worker return, dynamic role scaling, full terrain
preparation, recovery and large mixed-fleet acceptance. These remain required.
