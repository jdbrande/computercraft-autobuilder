# Autobuilder 0.25.0

Development direction: [full fleet requirements](docs/fleet-requirements.md) and
[milestone 1 autonomous exploration design](docs/autonomous-mining-design.md).
The full fleet roadmap remains in progress. The current release behavior is documented below.
See the [0.12.0 acceptance report](docs/validation-0.12.0.md) for automated and live Minecraft results.

**Automatic site preparation:** `build auto NAME` surveys, levels and clears the
required workspace, acquires missing foundation fill, and verifies each region
before construction. Retained structures can use restored temporary access to hidden
support; bounded fluid retries can schedule verified containment. See the
[0.23.0 acceptance report](docs/validation-0.23.0.md) for evidence and limits.

**Worker settlement:** projects finish only after linked work, cargo and worker
acknowledgements settle. Configure [home return buffers](docs/logistics.md#home-return-and-project-completion);
`worker return ID` requests an explicit return and `returns` shows blockers.

**Managed hauling:** [register logistics nodes](docs/logistics.md) for automatic
stock targets and reserved parallel couriers. `haul` requests a transfer and
`logistics` reports physical receipts, ownership and shortages.

**Loaded missions:** [configure chunk coverage](docs/chunk-loading.md) before dispatch.
Use stationary Advanced Peripherals chunky turtles or explicitly assured loaded
areas. `chunks` reports missing coverage and retained loader ownership.

**Automatic exploration:** [configure explorers](docs/autonomous-mining.md) with
`setup exploration` on the controller and `setup miner explore` on miners.
Several explorers can share one material request, search new sectors automatically,
return partial deliveries, and resume after restarts. `build auto NAME` feeds those
materials into the existing crafting and construction pipeline.

**Automatic materials and multiple miners:** [follow this guide](docs/material-team.md).
Use `setup miner stone,coal`, `setup miner sand`, and other resource profiles on
different turtles. `build auto NAME` gathers, crafts/smelts, builds and verifies.
The controller's **8** screen shows the material team. Full simplified cathedral
construction now streams small batches with `cathedral start X Y Z`; it requires
a prepared full-size site and configured material sources/factory.

**First time using this? [Start here](docs/start-here.md).** The guide shows the
hardware drawing and exactly what to place, click, and type. The controller now
has a numbered menu: `1` checks setup and `2` clears an automatic site, then runs
the bundled 28-block cathedral test. In controller `setup`, press Enter or type
`auto` at **Build corner**; manual `x y z` corners remain available. Configure the
chosen worker's actual coordinates and heading in its own `setup` (GPS is optional).

Release 0.10.5 fixes a scheduler stall where a yielding chest/modem call could
leave the test stuck at preparing with an empty job queue. Updating and rebooting
resumes the saved request; do not erase checkpoints or repeat setup.

A CC:Tweaked controller and Turtle system for Minecraft Java **1.20.1**. It plans
materials, acquires supported resources, runs crafting and furnaces, converts and
builds schematic projects, resupplies workers, verifies completed structures and
repairs supported mismatches. Work, inventory transfers and device ownership survive
restarts through checkpoints and operation journals.

Desktop tests exercise these workflows with stateful hardware simulations. The small
28-block pilot has completed in the user's local world; the new full autonomous
cathedral workflow has not had a live acceptance run. Unsupported blocks, inaccessible
cells, unavailable resources and uncertain recovery remain visible blocked work.

| Setup or workflow | Guide |
| --- | --- |
| Install, offline folders, update and rollback | [Installation](docs/installation.md) |
| First test: every placement, click and command, with drawing | [Start here](docs/start-here.md) |
| Guided controller/builder setup without editing Lua | [Quick setup](docs/quick-setup.md) |
| Multiple resource miners and automatic construction | [Material team](docs/material-team.md) |
| Miner hardware, bounded excavation and fuel | [Mining setup](docs/milestone-2.md) |
| Concurrent miners and durable area ownership | [Parallel mining](docs/parallel-mining.md) |
| Recipe planning, Crafty station and furnace bank | [Production](docs/production.md), [parallel Crafty stations](docs/parallel-factory.md) |
| Automatic fuel stations and rescue | [Fuel management](docs/fuel-management.md), [0.15.0 acceptance](docs/validation-0.15.0.md) |
| Inventory reservations and physical receipts | [Inventory ownership](docs/inventory-ownership.md), [0.14.0 acceptance](docs/validation-0.14.0.md) |
| Dependency graph and resource providers | [Resource planning](docs/resource-planning.md), [0.13.0 acceptance](docs/validation-0.13.0.md) |
| Sponge conversion, transforms and JSON format | [Blueprints](docs/blueprints.md) |
| Placement families, verification and repair | [Construction](docs/construction.md) |
| Builder resupply and chest-to-chest transport | [Logistics](docs/logistics.md) |
| Managed trees and crops | [Renewables](docs/renewables.md) |
| Configured depot footprint expansion | [Infrastructure](docs/infrastructure.md) |
| Simplified cathedral sections and first live pilot | [Cathedral plan](blueprints/classic-cathedral/README.md) |

## Hardware target

Use Java 17 with Minecraft Java 1.20.1 Forge. The existing compatibility target is:

| Component | Version / file |
| --- | --- |
| Forge | 47.4.10 |
| CC:Tweaked | `cc-tweaked-1.20.1-forge-1.120.2.jar` |
| Advanced Peripherals, optional scanner | `AdvancedPeripherals-1.20.1-0.7.48r.jar` |

Use the official [Forge downloads](https://files.minecraftforge.net/net/minecraftforge/forge/index_1.20.1.html),
[CC:Tweaked versions](https://modrinth.com/mod/cc-tweaked/versions?g=1.20.1&l=forge)
and [Advanced Peripherals release](https://github.com/IntelligenceModding/AdvancedPeripherals/releases/tag/1.20.1-0.7.48r).
Install matching Forge JARs into the instance/server `mods` folder. These are the
project's recorded dependency-compatible versions, not a live-tested modpack certification.
Fallback mining can run without Advanced Peripherals.

Use an Advanced Computer as controller and Advanced Turtles as workers, with wireless
modems for communication. Connect storage, furnaces and crafting-station chests with
wired modems; wireless networking does not transfer inventory items. Builders need
placement inventory and a suitable digging upgrade for repair. Miners need the
hardware described in the mining guide. Crafting requires a dedicated Crafty turtle
parked at its station with all 16 inventory slots empty.

Keep devices, GPS hosts and working areas loaded, in the same dimension and modem
range. No chunk loader is provided. Rednet IDs/protocol strings are routing filters,
not authentication; use this on a trusted server.

## Install and update

The project is hosted at [jdbrande/computercraft-autobuilder](https://github.com/jdbrande/computercraft-autobuilder).
The commands below use that repository. To prepare a fork, change the raw URL with:

```sh
python3 tools/release.py --base https://raw.githubusercontent.com/jdbrande/computercraft-autobuilder/main --version 0.12.0
```

Publish `installer.lua`, `update.lua`, `startup.lua`, `manifest.json`, and
`autobuilder/` together. In CraftOS, install the controller:

```text
wget run https://raw.githubusercontent.com/jdbrande/computercraft-autobuilder/main/installer.lua controller
```

Run `id` on it. On a Turtle, substitute that ID for `7`:

```text
wget run https://raw.githubusercontent.com/jdbrande/computercraft-autobuilder/main/installer.lua builder 7
```

Profiles are `controller`, `worker`, `miner`, `builder`, `logger`, and `courier`.
All Turtle profiles use `role='worker'`. New builder/logger/courier installations
set their corresponding `automation` capability. Generic workers and miners still
require explicit capability/hardware settings. **Mining remains opt-in for every
profile.** Installation itself does not move a Turtle.

The installer creates `/startup.lua`, `/update.lua` and managed `/autobuilder/`
files. For controller/builders, follow [Start here](docs/start-here.md). After
updating and rebooting, type `setup` inside the running controller app, then do
the same on one registered worker. Each wizard returns to the app automatically.
The wizard detects inventories/GPS, retrieves supply settings from the controller,
loads the builder's slot-15 fuel after confirmation, and enables building. Supply
**16 coal/charcoal or 2 coal blocks**; setup stops at at least **1,000 fuel**, leaving
extra items (two blocks give 1,600 from empty with default fuel values). Other roles use
`/autobuilder/settings.lua`. Updates preserve settings byte-for-byte; older
logger/courier installations must enable their capability explicitly. Do not put
local values in `config.lua`.

Stop Autobuilder with **Q**, close other Autobuilder tabs, then update:

```text
cd /
update
reboot
```

Use `/update.lua` from any directory. The updater checks versions and actual SHA-256
hashes while preserving settings, checkpoints, logs and a customized root startup.
For an interrupted installation, run `/installer.lua --recover`; if that installer
is missing, use `/.autobuilder-install/transaction/recover.lua`. The
[installation guide](docs/installation.md) preserves all fallback and offline recovery steps.

For an offline installation, generate a new directory on the desktop:

```sh
python3 tools/release.py --offline dist/controller --role controller
python3 tools/release.py --offline dist/builder-12 --role builder --controller 7
```

With Minecraft/the server stopped, copy the directory's **contents**, including
`autobuilder/.installation.json`, into an empty
`saves/<world>/computercraft/computer/<computerID>/` directory. The result must be
`<computerID>/startup.lua`, not `<computerID>/controller/startup.lua`. Dedicated
servers use `<configured-world-folder>/computercraft/computer/<ID>/`. Follow the
installation guide when replacing an existing computer directory; never copy
another computer's `autobuilder/data/` or overwrite saved settings/state.

## Configure a production and building setup

The settings examples below use a manual build origin. The beginner pilot's AUTO
mode instead chooses an 8 × 8 footprint starting two blocks behind its builder,
which must be parked with its front against the supply chest. It clears the build
layer at the turtle's height and two layers above, plus an 8 × 10 overhead rectangle
over the depot-to-footprint route and the depot shaft. Ground below remains.
These fixed bounds never expand. This pilot preparation is separate from the
global **`clearSite`** setting, which can remain `false`; it does not enable general
clearing for other projects.

Automatic pilot clearing accepts only common natural terrain and refuses
containers, machines, ores, liquids, waterlogged blocks and protected blocks/areas.
Keep other workers and players away. Drops remain in cargo slots 1–14; a full
inventory stops work. `3` pauses clearing or building and `4` resumes it. Empty
cargo only for an ordinary inventory-full stop; **leave inventory and the target
block unchanged if a dig outcome is unresolved or ambiguous**. See
[Start here](docs/start-here.md) for the update and setup sequence.

Replace every coordinate and peripheral name below with your actual layout. The
controller needs wired access to source storage, the furnace bank and an initially
empty supply chest. That supply chest must also be adjacent to the builder's depot
stand on its configured side. Keep the source storage and staging chest distinct.

Controller `/autobuilder/settings.lua`:

```lua
return {
  role = 'controller',
  storageInventories = {'minecraft:chest_0'},
  furnaces = {'minecraft:furnace_0'},
  smeltingFuelItem = 'minecraft:coal',
  turtleFuelReserveItems = {['minecraft:coal']=64},
  supply = {inventory='minecraft:chest_1', side='front', batch=64},
  depot = {x=100,y=64,z=-200,heading='north'},
  build = {enabled=true, origin={x=110,y=64,z=-200}, rotation=0},
  clearSite = false,
}
```

Builder `/autobuilder/settings.lua`:

```lua
return {
  role = 'worker', controllerId = 7, label = 'Builder01',
  automation = {building=true},
  gps = {enabled=true, timeout=2, interval=30},
  initialPosition = {x=100,y=64,z=-200,heading='north'},
  depot = {x=100,y=64,z=-200,heading='north'},
  supply = {inventory='minecraft:chest_1', side='front', batch=64},
  clearSite = false,
}
```

`initialPosition` is used only on first boot. Use the Turtle's actual block coordinates
and facing, not the player's position. Axes are +X east, +Y up, +Z south; headings are
`north`, `east`, `south`, `west`. GPS supplies coordinates but cannot infer a stationary
Turtle's heading. Provide fuel and a clear overhead corridor between depot and site.
Navigation never digs a passage. Protect infrastructure with inclusive
`restrictedAreas={ {min={x=...,y=...,z=...},max={x=...,y=...,z=...}} }` boxes.

For a separate crafting worker, use `automation={crafting=true}`, configure the same
source `storageInventories`, and set its `craftingStation` input/output wired names
and sides. Park it between those dedicated empty chests; its executor does not move
it into position. The [production guide](docs/production.md) gives the exact layout.
Use separate mining/farming workers as needed. Configure managed `treeFarms`/`farms`
on the controller and enable `logging`/`farming` on those workers. Add
`automation={courier=true}` and controller `locations` for transport workers.
Existing settings can enable several capabilities, but only one owned task runs on
a worker; crafting's empty-inventory requirement makes a dedicated station practical.

Start manually with `/autobuilder/controller.lua` on the controller,
`/autobuilder/workers/worker.lua` on a Turtle, or `/autobuilder/startup.lua` on either.
**Q** saves and returns to the shell; **Shift N/P** page controller details.
Settings changes take effect on the next launch. Reboot uses the root startup launcher.

## Request materials and build a project

Enter these commands in the running controller, not the CraftOS shell:

```text
request minecraft:stone_bricks 1000
resources
jobs
errors
```

Requests subtract live stock, expand registered crafting/smelting recipes and acquire
missing supported resources. Mining and managed farms require configured capable
workers. Unknown materials remain special acquisition requirements. To try production
without mining, preload raw ingredients and fuel into source storage. The reserved
coal quantity above remains unavailable to recipes; supply additional smelting fuel.

Copy a Sponge v2/v3 `.schem` directly into the controller filesystem. With
`build.enabled` and the build origin configured, start the normal automatic pipeline:

```text
build /house.schem
```

The controller parses raw/gzip NBT, saves a validated JSON snapshot and plans all
materials before work starts. Repeating the command reports the same project;
changed source bytes require a new project name. To inspect before starting:

```text
build import /house.schem house
build analyze house
build auto house
```

Bounds, source offsets and unsupported entity/biome data are documented in
[Importing blueprints](docs/blueprints.md). Desktop conversion is also available
using Python's standard library:

```sh
python3 tools/schem_converter.py house.schem house.json
```

Copy `house.json` into the controller's filesystem, for example as `/house.json`.
Then use:

```text
build import /house.json house
build analyze house
build materials house
build simulate house
build prepare house
build status house
```

Analyze/materials/simulate do not move Turtles or transfer items. They expose material
requirements, unsupported states and estimates. Wait until prepare reaches `ready`,
then run:

```text
build start house
build status house
build verify house
build repair house
```

Start builds dependency-ordered regions, obtaining materials at the depot when needed.
It automatically verifies the complete transformed volume afterward, including air.
A project becomes `built` only when that verification has no defects; otherwise it
reports `needs_repair`. Explicit verify and repair start after prior project tasks
finish. Use `build pause house` / `build resume house` to control owned project work.
Use `pause <task-id>` / `resume <task-id>` for supported individual tasks.

With `clearSite=false`, unwanted blocks in schematic air cells are reported and
left intact. With `clearSite=true` on controller **and** builder, start/repair clears
those cells and repairs wrong wanted blocks before final verification. The explicit
`build clear house` command is also gated by that setting. Clearing never expands
outside listed schematic air cells and still refuses protected blocks and containers.

Other controller commands include `mine minecraft:raw_iron 100`,
`transport minecraft:stone 64 source destination`, and `expand`. Transport uses named
controller locations above actual source/destination chests. Expansion requires an
explicit `depotExpansion` block plan. See the focused guides before assigning these.
With `autoDepotExpansion={enabled=true,freeSlots=2}`, low empty-slot capacity triggers
that plan once, followed by verification. This builds the configured footprint;
install and wire additional containers separately. See [infrastructure setup](docs/infrastructure.md).

## Practical limits

The converter is bounded to 262,144 cells and 32 MiB input; it preserves block states
but does not migrate game versions or restore entities, inventories, sign text or
other block-entity NBT. Import reports these limitations. Project copies are hash
checked; import changed blueprints under a new name.

Placement supports registered vanilla cubes and constrained logs, slabs, straight
stairs, gravity blocks, torches, carpets, panes/fences, lanterns, ladders and isolated
left-hinged closed doors. Support/access checks and observed final states determine
success. Waterlogged variants, double slabs, connected stair shapes, general door
layouts, beds, rails, fluids and block entities remain unsupported. See the exact
[construction matrix](docs/construction.md); recipe availability does not imply that
its output has a placement strategy. Enclosed cells can remain inaccessible.
A full builder inventory blocks resupply or repair; unload unneeded cargo and resume
after any outstanding action is reconciled. Builders do not automatically unload cargo.

Managed farms cover wheat, bamboo, cactus, sugar cane and single-column oak/birch/
spruce trunks. They require prepared sites and planting stock; they do not search
wild terrain, chase branches, grow 2×2 trees or handle underwater kelp. Separate
miners can own disjoint bounded areas, while shared movement and inventory access
remain coordinated. Disconnected workers retain their assignments until reconciled.

## GPS setup


Follow the [CC:Tweaked GPS guide](https://tweaked.cc/guide/gps_setup.html). Place four
computers with wireless modems at accurately known block coordinates, with one host
outside the plane of the other three. They must be in range and remain loaded.
Use F3's **Targeted Block** coordinates of each host, not the player's feet.

For example, four host coordinates could be `(100,100,-200)`, `(104,100,-200)`,
`(100,100,-196)`, and `(100,104,-200)`. On each host create its own `/startup.lua`:

```lua
shell.run('gps', 'host', 100, 100, -200) -- replace with THIS host's coordinates
```

Do not put Autobuilder's startup on these dedicated GPS hosts. Run `gps locate`
on the turtle to check the constellation, then start the worker. GPS polls every
30 seconds by default. During outages, a previous position is displayed as `local`;
without any known coordinates it displays `position unknown`. Outages do not stop
registration or heartbeats. A GPS coroutine receives separate copies of events,
so locating cannot consume the networking coroutine's messages.

## Recovery and diagnostics


Local files are `/autobuilder/data/controller.state` or `worker.state`, with `.bak`
and temporary `.tmp` companions. Logs are `/autobuilder/logs/<role>.log` and up to
three rotated backups. Log levels: DEBUG, INFO, WARN, ERROR. Snapshots serialize with
CC:Tweaked `textutils`, a schema version and Adler-32 integrity check.

A save writes and validates the temporary file, retains the previous valid primary
as backup, then promotes the temporary file. This protects against common interrupted
writes; it cannot promise filesystem durability beyond Minecraft's own world saves.
If primary is corrupt, a validated backup is loaded and a warning is logged. If
neither is valid, startup stops with an error instead of silently resetting state.
A leftover temporary file without any committed snapshot also stops startup.
Preserve these files before investigating disk failures. Never delete state as the
normal way to restart.

Every navigation move saves an intent before touching hardware and saves its result
afterward. An interrupted operation leaves the pose uncertain. GPS resolves an
interrupted translation, but an interrupted turn still needs heading confirmation.
Any **worker backup recovery** invalidates heading and position, because its snapshot
may predate the movement intent. Stationary telemetry continues during recovery.

For manual recovery, quit the application with Q, determine the turtle's actual block
coordinates and facing, then run, for example:

```text
/autobuilder/pose.lua 100 64 -200 north
/autobuilder/startup.lua
```

This records the pose without moving the turtle. Use this after physically moving
or rotating a turtle outside the navigation API too. `initialPosition` cannot
override an existing checkpoint. Saved tasks resume from their persisted phases and
action journals. Ambiguous pose
blocks movement until GPS or operator confirmation resolves it. Crafting, smelting,
placement, harvesting and cargo transfers reconcile observed blocks/inventories
before repeating a possibly completed action. Preserve both inventory contents and
checkpoint files when an operation reports an ambiguous result.

## Desktop verification and live acceptance

Run the Lua suite with Lua 5.2+ or the pinned desktop runtime:

```sh
lua tests/run.lua
# Or:
python3 -m venv .venv
.venv/bin/pip install -r tests/requirements.txt
.venv/bin/python tests/run.py
.venv/bin/python -m unittest discover -s tests -p 'test_*.py'
python3 tools/release.py --check
```

Python/Lupa is only for desktop tests. Install no Python or external Lua packages
on ComputerCraft. Tests model changing blocks/inventories, furnace progress,
controller/worker messages, duplicate delivery, partial transfers, full chests and
interruption at checkpoint boundaries. They do not certify live mod behavior.

Before larger jobs, use a disposable world to confirm registration/GPS, loaded-chunk
behavior, actual peripheral names, one furnace/craft cycle, a small schematic with
verification and gated repair, and one courier trip. Test worker/controller reboot,
full destination storage and missing supply without deleting checkpoints. Run the
[mining acceptance checklist](docs/milestone-2.md) before excavation. Keep backups
when testing corrupted-checkpoint or interrupted-install recovery.

Interrupted movement: [GPS pose recovery](docs/pose-recovery.md) and [0.20 acceptance](docs/validation-0.20.0.md).

Dynamic scaling0.24 acceptance: [48-block native trial and release evidence](docs/validation-0.24.0.md).

Mining intelligence0.25 acceptance: [persistent exploration evidence and native results](docs/validation-0.25.0.md).
