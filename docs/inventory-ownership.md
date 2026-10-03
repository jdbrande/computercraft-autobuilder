# Inventory ownership

New factory jobs reserve their complete input/fuel contract before a crafting
worker can receive an assignment or a furnace can transfer items. Competing jobs
wait for enough unreserved physical stock. A reservation survives controller
restart and an offline owner; it never expires merely because a worker is quiet.

Use `resource minecraft:stone` on the controller. Its first line distinguishes:

- `stock`: measured items in configured shared inventories.
- `available`: physical stock minus unwithdrawn grants, floored at zero.
- `reserved`: granted inputs still awaiting confirmed withdrawal.
- `transit`: explicitly recorded logistics payloads (factory inputs in a machine
  are processing inputs, not moving logistics payloads).
- `expected`: promised factory output not yet delivered.
- `demand`: aggregate graph demand of active production requests, including their
  ingredient needs. This is an active-request forecast, not already placed blocks.

The production screen shows how many inventory claims remain held. A failed
storage read makes stock/available unknown. Graph snapshot values remain visible
separately; forecasts never increase available stock.

Crafty workers and furnaces report cumulative quantities after their physical
transfer journals reconcile. Partial receipts reduce reserved inputs and expected
outputs. Repeated reports are idempotent; older reports cannot restore old transit
counts, and changed duplicate reports are rejected. Confirmed completion releases
unused input claims. Checkpoint failures stop changes without dropping ownership.

The existing factory execution barrier remains. Count reservations alone do not
make whole-chest transfer observations safe under concurrent writes. Independent
station staging and destination-capacity reservations are later integration work.
Older saved factory jobs keep their existing exclusive execution path. Old Crafty
workers can complete under that barrier without partial receipts; their claims
remain conservative until their exact-output completion acknowledgement arrives.

The ledger foundation supports in-transit quantities, but this milestone does not
yet reserve courier pickups or destination capacity. Those belong with the fuel
logistics and parallel factory milestones. Do not delete claims to unblock an
unknown owner; reconcile the physical worker and its task first.
