# Automatic fleet fuel

Enable automatic station replenishment, depot refueling and courier rescue with
`fuel.enabled=true` on the controller and participating workers. Workers keep their
ordinary roles. A courier needs `automation.courier=true`, a wireless modem, known
position/heading, a configured depot and enough starting fuel to return safely.

## Stations and startup fuel

Each station has one dedicated chest above its worker's depot stand. Connect the
chest and controller to a wired inventory network. Keep the stand and at least one
side approach clear; the normal approach uses the west side unless protected.
A deposit/returned-container chest may remain below the stand. Give each courier
its own station. Shared stock, supply staging, crafting input/output and furnace
inventories cannot also be fuel stations.

Controller example (merge these fields into `/autobuilder/settings.lua`):

```lua
storageInventories = {'minecraft:chest_0'},
fuel = {
  enabled = true, item = 'minecraft:coal', low = 200, target = 1000,
  stations = {
    {id='courier', workerId=12, inventory='minecraft:chest_1',
     position={x=0,y=64,z=0}, targetItems=16},
    {id='miner', workerId=13, inventory='minecraft:chest_2',
     position={x=8,y=64,z=0}, targetItems=16},
  },
},
```

Worker example:

```lua
depot = {x=0,y=64,z=0},
fuel = {enabled=true, low=200, target=1000},
automation = {courier=true},
```

An already configured, registered worker can run `setup fuel` to copy the
controller's fuel policy. The wizard preserves its depot and roles, asks before
saving, and performs no movement or refueling. Reboot after editing settings or
finishing shell setup. Setup refuses active recovery and unsettled rescue owners.

Stock source chests with initial fuel and give at least one courier enough finite
fuel for pickup, delivery, return and reserve. The controller replenishes missing
fuel through ordinary production/acquisition requests. Coal can come from mining;
charcoal can come from the configured tree and smelting chain. A fleet with no
stored fuel and no fueled producer cannot bootstrap itself; `fuel` shows that wait.
Factory recipes protect `turtleFuelReserveItems`; fuel-purpose station claims may
use that reserve.

## Monitoring and recovery

Run `fuel` on the controller for station stock, fill/refuel job owners, worker fuel,
required fuel, courier mission budgets, delivered quantities, recipient recovery
stage and errors. Shift N/P changes pages. Stock is the last physical station
observation, not an estimate of items still present while a consumer owns it.

Station filling reserves source stock, checks native slot/item capacity and saves
an intent before transferring. The receiving worker cannot consume the chest until
filling reconciles. Each managed refuel consumes a finite station batch and releases
the chest for replenishment. The controller repeats batches until measured fuel
reaches the target, even when `targetItems` is small or fuel estimates differ from
native values. Offline owners retain their assignments and station ownership.

A stranded worker freezes at a confirmed pose without losing its original task.
A suitable idle courier reserves its station pickup, verifies the recipient's
computer ID before dropping fuel, and returns home. The recipient measures the
added items and journals their consumption. Only enough measured fuel and a settled
rescue permit a task blocked on fuel to resume automatically. Partial deliveries,
duplicate messages and reboots preserve these receipts. A blocked route, full
receiver, unknown pose or changed inventory remains visible; other work may continue.
Do not remove a live rescue's inventory or reset its checkpoint to clear the error.
After fixing a physical obstruction, use `resume <courier-task-id>`.

Configured energy values guide quantity estimates; actual `getFuelLevel` determines
readiness. Defaults cover coal/charcoal80, coal blocks800 and lava buckets1000.
Override `fuel.values` and `fuel.returns` for supported modded fuels. Ordinary
refueling uses slot15 and never burns arbitrary building inventory. Returned
containers must be unloaded into a verified chest below the depot before a managed
refuel job releases its worker. For a Crafty station, keep this return chest distinct
from crafting input/output (use front/up sides as appropriate). Ordinary in-field
refueling retains containers until depot return. Rescue fuel
is consumed from measured receiving slots; returned buckets remain in inventory.

Chunk loading is still a separate milestone. Keep the whole mission loaded. Routes
stop at unknown obstructions and protected cells; rescue does not dig a new access
shaft. Larger traffic planning, automatic inventory recovery and workload scaling
remain tracked in [fleet progress](fleet-progress.md). See the
[implementation contract](fuel-management-design.md) and
[0.15.0 acceptance](validation-0.15.0.md) for evidence and limits.


## Mission budgets and proactive refueling

`fuel` now shows a scoped budget for each owned or next compatible queued mission:
current fuel, outward travel, work, return and reserve. The summary is for the next
bounded excursions, not a promise of whole-project fuel cost. One prospective job
is counted once; suitable already-fueled workers are preferred. Offline ownership
is retained but its stale fuel is reported as unknown. Missing position or route
geometry is explicit, never a zero-cost movement estimate.

With automatic fuel enabled, ordinary new assignments must have enough fuel for
that budget. The check repeats after yielding coverage observations. An idle worker
above `fuel.low` still receives a managed refuel task when its next ready mission
needs more. Its target rises to the mission requirement if necessary. Station
batches, inventory claims and measured refueling remain unchanged. Native tank
limits cap configurable targets; a mission beyond that capacity shows its required
fuel and the limit instead of repeatedly topping up a full tank.

Construction budgets retain the existing largest-next-target excursion, including
clearance, approach, temporary access, depot return and reserve. They allow normal
refueling between targets. Mining and harvesting likewise forecast bounded work
before safe return; hauling covers one cargo trip. Rescue and home/station travel
retain their existing recovery rules. Dynamic obstructions can increase actual
travel and still invoke the navigation reserve stop. Forecast fuel-item quantities
are estimates; only observed station stock and transfer receipts are physical fuel.
Optional task-bound budget telemetry remains compatible with older worker reports.


Miners advertise their departure fuel target and entry in optional validated telemetry;
update workers with the controller to obtain those per-worker route forecasts.
Initial assignments and prospective exploration include that departure target;
ongoing trips budget their remaining work rather than another fresh departure.
Exploration's bounded planner exposes prospective fuel needs even before a trip
can be created. The initial exit/route lower bound may rise when a detour is found;
no additional route search or speculative ownership is created by the fuel view.
Paused/completed groups and changed worker homes/envelopes invalidate those hints.
Queued jobs that cannot currently dispatch do not hide ready work, and a turtle
whose native tank cannot hold the requirement does not mask a capable alternative.
Home travel with automatic fuel enabled uses the station side approach, including
mixed cargo returns. Keep that approach clear as described in the station setup.
