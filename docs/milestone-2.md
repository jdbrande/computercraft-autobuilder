# Milestone 2: mining and depot logistics

The controller now accepts `mine minecraft:raw_iron 100`. It means **ensure 100 raw
iron in the configured depot inventories**, using stock already there. It does not
mean gather 100 more regardless of current stock. The planner gathers the shortfall,
and the controller checks actual storage before declaring the request complete.

This implementation has offline simulation coverage. Live Minecraft acceptance has
not been run; use the checklist below in a test world first.

## Hardware layout

Use the versions and installation procedure in the [main README](../README.md).
For the mining worker, install a **diamond pickaxe on the left** and a **wireless
modem on the right**. Put a Geo Scanner item in **inventory slot 16**. The software
swaps the left pickaxe for that scanner only while scanning, then restores the
pickaxe. The modem remains installed. If your pickaxe is on the right, configure
`scanner.side='right'` and put the modem on the left. Modem-side swaps are refused.

Slot **15** is reserved for coal, charcoal or coal block fuel; slot **16** is reserved for the
scanner/displaced pickaxe. Leave both slots alone during a job. Other slots are
cargo. For a fallback-only worker, slot 16 can be empty: it will use bounded strip
mining and inspect adjacent ores. It still needs the pickaxe and wireless modem.

A concrete depot layout, viewed from the side:

```text
               fuel chest (100,65,-200), coal/charcoal/coal blocks only
                       |
controller -- cable -- worker parking position (100,64,-200), facing east
                       |
               output chest (100,63,-200)

Cleared route at y=64 from worker parking position to mine entry (104,64,-200).
Mine bounds example: x=104..119, y=60..68, z=-200..-185.
```

The output chest needs a wired modem, connected through networking cable to a wired
modem on the controller. Activate the chest's wired modem with a right click; note
its inventory name, for example `minecraft:chest_0`. The controller also needs its
wireless modem. A turtle does not need a wired modem: it unloads downward. The chest
beneath it must be a vanilla chest, trapped chest, or barrel; otherwise it refuses
to drop. The dedicated fuel chest above is optional if slot 15 has enough fuel.
Do not include the fuel chest in `storageInventories`, because its coal is reserved
for movement rather than available building stock.

Place GPS hosts outside the mine bounds. Keep the controller, hosts, mine and depot
loaded and in wireless range. Chunk loading and wireless relays are not supplied.
Choose bounds which actually contain the resources needed; no program can find iron
in a bounded test region that contains none. For early testing, use a controlled vein
near the mine entry. Production depth is configurable through the entry coordinate.

## Controller settings

```lua
return {
  role = 'controller',
  storageInventories = {'minecraft:chest_0'}, -- use your actual wired name
}
```

Start `/autobuilder/controller.lua`. The controller starts with the worker screen.
Type `resources` and press Enter to verify the wired inventory is visible. A missing
inventory is an error, not a zero count; new work waits for a valid inventory snapshot.

## Worker settings

Run `id` on the controller and replace **7** below. These coordinates are an example:
set them to your actual block coordinates. On an existing installation, quit and use
`/autobuilder/pose.lua x y z heading` to correct the saved pose; `initialPosition`
applies only on first boot.

```lua
return {
  role = 'worker',
  controllerId = 7,
  label = 'Miner01',
  initialPosition = {x=100, y=64, z=-200, heading='east'},
  depot = {x=100, y=64, z=-200},
  minimumFuelReserve = 100,
  scanner = {side='left', slot=16, radius=8, cooldown=3, ttl=15, maxWait=30},
  mining = {
    enabled = true,
    entry = {x=104, y=64, z=-200},
    bounds = {min={x=104,y=60,z=-200}, max={x=119,y=68,z=-185}},
    fallback = true,
    maxSurveySteps = 256,
    pathBudget = 4096,
    fuelTarget = 1000,
    returnMargin = 8,
  },
  -- Inclusive boxes; do NOT protect the air block where the turtle parks.
  restrictedAreas = {
    {min={x=100,y=63,z=-200}, max={x=100,y=63,z=-200}}, -- output chest
  },
}
```

`mining.enabled` defaults to false, so updating a Milestone 1 installation does not
begin excavation on its own. A worker still requires an explicit controller job.
The controller selects and retains one mining worker for this milestone. More workers
can register for telemetry, but parallel excavation and collision reservations remain
Milestone 8. Do not run multiple controllers against the same physical mine/depot.

All mining workers should use the same reviewed software/configuration version as the
controller. `capabilities.mining` is enabled by the validated mining configuration.

## Commands

Enter these into the running controller and press Enter:

```text
mine minecraft:raw_iron 100
jobs
resources
workers
status
resume <jobId>
replan <jobId>
```

`jobs` shows job ID, status, assigned worker, delivered quantity, target stock and
errors. `resources` shows actual depot counts. N/P changes pages when the input is
empty. Q saves and quits at the end of any active hardware step. Ctrl+T or abrupt
shutdown can interrupt hardware operations; recovery uses the saved intent.

Use `resume <jobId>` after fixing a blocked worker (for example, empty a full output
chest or replenish fuel). It does not discard progress. Missing pose recovery resumes
automatically when GPS can resolve the position; ambiguous heading still requires
operator confirmation with `pose.lua` on the worker. The command buffer accepts pasted
job IDs. There is no separate shell `mine` executable; the command belongs to the
running controller's terminal interface.

If another consumer removes stock during mining, the completed delivery is recorded
and a fresh, uniquely identified supplemental job gathers the newly missing amount.
Lost ACKs replay completion, not excavation. Automatic supplementation is limited to
three generations to avoid endless work against a continually draining chest. If that
limit is reached, stop the competing consumer and use `replan <jobId>` on the blocked
leaf job named in the queue. Normal replenishment needs no manual replan.

Supported requested drops:

| Item | Target blocks |
| --- | --- |
| `minecraft:raw_iron` | iron ore, deepslate iron ore |
| `minecraft:coal` | coal ore, deepslate coal ore |
| `minecraft:raw_copper` | copper ore, deepslate copper ore |
| `minecraft:raw_gold` | gold ore, deepslate gold ore |
| `minecraft:diamond` | diamond ore, deepslate diamond ore |
| `minecraft:redstone` | redstone ore, deepslate redstone ore |
| `minecraft:lapis_lazuli` | lapis ore, deepslate lapis ore |
| `minecraft:cobblestone` | stone, cobblestone |
| `minecraft:cobbled_deepslate` | deepslate, cobbled deepslate |

Definitions and depth hints are centralized in `resources/materials.lua`. Actual
collected inventory is counted, including variable ore drops. A final drop may exceed
the exact target by a few items; the turtle stops once it has enough.

## Mining, safety and recovery behavior

- Scanner results use absolute world coordinates internally, cache by scan origin and
  expiry, and invalidate on digging. Adjacent matching ore blocks form ranked veins.
  The AP 0.7 `geoScanner` API returns relative offsets. Scans must have zero reported
  cost in this milestone so they cannot consume the return-fuel reserve. Radius 8 is
  the default; lower it if your server changes the free radius.
- The adapter uses AP `getOperationCooldown('scanBlocks')` when available and waits
  while the scanner remains installed. It also rate-limits attempts locally and
  caps waits. Networking continues during hardware waits. Failed tool restoration
  blocks the job rather than continuing fallback without a pickaxe.
- A* stays inside the configured excavation bounds, avoids protected/observed blocked
  cells, and caches the current route. Each actual step inspects the next block;
  unexpected protected obstacles invalidate the route and trigger replanning.
- Only allowlisted terrain and ore can be dug. Vanilla containers, bedrock, liquids,
  spawners, turtle blocks, all `computercraft:` blocks, protected names and restricted
  coordinates take precedence over the excavation allowlist. Custom allowlists replace
  defaults. The route between depot and entry must be player-cleared; no excavation
  occurs outside mining bounds.
- Without usable scans, a bounded strip survey operates at the configured entry Y,
  advancing from entry Z toward the maximum Z with rows three blocks apart. It inspects
  neighboring blocks along the route. This is not an unbounded quarry or global depth
  search. Exhausting that area returns to depot and reports an incomplete quantity.
- Inventory pressure or low fuel triggers return along the saved breadcrumb route.
  Cargo unloads into the chest below, fuel is taken from the reserved slot and optional
  chest above, then the turtle retraces its route and resumes. Refueling and retries
  have limits and report failure rather than looping indefinitely.
- Each physical move journals the mining breadcrumb change as well as the navigation
  intent. Each drop journals its slot, name and count. Reboot recovery reconciles
  actual pose/inventory against that journal before accounting progress. Do not edit
  cargo or move/rotate the turtle externally during recovery.
- The controller saves assignment ownership before sending. Workers retain completed
  jobs until acknowledged and persist completed IDs. Offline workers retain ownership;
  another turtle is never sent to duplicate an unobserved job. If controller backup
  recovery predates assignment, a matching registered worker task restores ownership
  and its original quantity before progress is accepted.
- GPS waits for a hardware boundary. Fixes sampled before intervening movement are
  discarded. Normal reboot can resume using trusted local coordinates when GPS is
  temporarily absent. Corrupt-checkpoint backup recovery still invalidates pose.

API references: [Geo Scanner](https://docs.advanced-peripherals.de/0.7/peripherals/geo_scanner/),
[AP 0.7.48r cooldown implementation](https://github.com/IntelligenceModding/AdvancedPeripherals/blob/1.20.1-0.7.48r/src/main/java/de/srendi/advancedperipherals/common/addons/computercraft/owner/OperationAbility.java),
and [CC:Tweaked inventory peripherals](https://tweaked.cc/generic_peripheral/inventory.html).

## New modules

```text
controller UI -> mining_service -> jobs -> validated rednet assignments
                        |                       |
                 storage snapshots       worker action coroutine
                                                |
                              miner state machine + checkpoint journals
                              /       |         |          \
                       scanner    A* paths   inventory   navigation
                      swap/cache              drops/fuel  turtle movement
```

`core/jobs.lua`, `core/mining_messages.lua`, `core/mining_service.lua`,
`core/pathfinding.lua`, `resources/materials.lua`, `resources/scanner.lua`,
`resources/miner.lua`, `storage/inventory.lua`, and `storage/storage.lua` are new.
Config, runtime, network and UI integrate them without adding mining code to entry points.

## Test checklist

Run the full offline suite from the project root:

```sh
.venv/bin/python tests/run.py
```

The simulator exercises actual module logic against a block world, physical turtle
pose, item stacks, fuel, scanner, chest stock and rednet messages. It covers normal
mining, restarts mid-job, drop/move journal recovery, lost completion ACKs, supply
shortfalls, blocked chests, scanner swapping/cooldowns, GPS concurrency and rerouting.
It does not model Minecraft physics or prove Forge compatibility.

In a live disposable world:

1. Complete the README telemetry/GPS checks with mining disabled.
2. Install the tool/modem/scanner, output chest, fuel chest, wired storage and bounds.
   Enable mining. Confirm `resources` counts items placed in the output chest.
3. Place a small iron vein inside bounds. Issue `mine minecraft:raw_iron 5`; verify
   stock reaches five, turtle returns, and scanner/pickaxe end in their proper places.
4. Repeat the same command: no additional excavation should occur.
5. Add enough available ore and issue `mine minecraft:raw_iron 100`.
6. Reboot the worker and controller separately mid-trip; confirm the same job resumes.
7. Fill the output chest. Confirm the job blocks without dropping cargo into the world;
   free space, then resume the job ID.
8. Test a small fuel stack plus a stocked fuel chest and confirm replenishment.
9. Remove/disable scanner with the worker stopped, leave slot 16 empty, and test fallback.
10. Place bedrock, a chest, a turtle and a protected coordinate in possible paths. Confirm
    they remain intact and the miner reroutes or reports a block.
11. Temporarily remove GPS hosts and then restore them; verify heartbeats continue and
    a later fix does not undo recorded movement.
12. Remove a little output stock during work; verify a supplemental job fills the gap.

The next milestone is recipe-driven crafting, smelting and fuel planning. Schematic
import, builders, couriers and parallel mining are not implemented here.
