# Autonomous ComputerCraft Schematic Construction Fleet

## 1. Project goal

Build a highly autonomous ComputerCraft turtle fleet that takes a schematic, determines everything needed to construct it, gathers missing resources, processes raw materials, crafts required items, supplies builders, constructs the schematic, verifies the completed structure, and recovers from routine failures with minimal player involvement.

The intended player workflow should eventually be close to:

```text
build castle.schem
```

The player should select or confirm the build location, then the fleet handles the remaining work.

The system should support large numbers of turtles working together without requiring the player to manually assign every turtle, identify every ore deposit, distribute every stack of materials, refuel each turtle, or restart individual jobs.

The existing exploration milestone remains part of this design. The current code already has production, jobs, mining, scanning, workflow coordination, crafting, smelting, and construction concepts. The new design should extend those systems instead of replacing them with an unrelated scheduler or framework.

---

# 2. Desired end-to-end workflow

The complete system should operate approximately as follows:

```text
SCHEMATIC
    |
    v
SCHEMATIC ANALYZER
    |
    v
MATERIAL REQUIREMENTS
    |
    v
DEPENDENCY PLANNER
    |
    v
CURRENT STORAGE CHECK
    |
    v
SHORTAGE CALCULATOR
    |
    +-------------------------------+
    |               |               |
    v               v               v
MINING          HARVESTING      CRAFTING
    |               |               |
    +---------------+---------------+
                    |
                    v
              PROCESSING
                    |
                    v
             CENTRAL STORAGE
                    |
                    v
              LOGISTICS
                    |
                    v
           BUILDER TURTLES
                    |
                    v
              VERIFICATION
                    |
             +------+------+
             |             |
          COMPLETE      DEFECTS
                           |
                           v
                       REPAIR
```

The entire system should work as a continuous pipeline instead of a strict sequence.

Mining, harvesting, processing, crafting, logistics, and building should occur concurrently whenever dependencies allow.

---

# 3. Primary design principles

The architecture should follow these principles.

## 3.1 Central coordination

Use a controller as the source of truth for:

- projects
- turtles
- assignments
- resource demand
- inventory
- exploration sectors
- build regions
- reservations
- worker capabilities
- worker health
- task dependencies
- recovery state

Workers should perform assigned physical actions.

Workers should not independently claim arbitrary mining or construction territory without controller authorization.

This matches the existing exploration design, where the controller assigns finite search sectors instead of allowing every miner to roam independently.

## 3.2 Persistent state

Any action affecting the world should have sufficient persisted state to recover after:

- server restart
- controller restart
- turtle restart
- modem interruption
- duplicate network packet
- lost acknowledgment
- turtle disconnect
- partial inventory transfer

The existing exploration design already requires assignment geometry and worker ownership to survive restarts.

Extend the same principle throughout the entire fleet.

## 3.3 Measured physical results

Never credit resources because a turtle expects to obtain them.

Count resources after confirmed physical transfer into managed inventory.

The current mining design already follows this rule. Deposited quantities are counted through refreshed stock snapshots rather than predicted drops.

Use the same model for:

- mining
- harvesting
- crafting
- smelting
- logistics
- construction

## 3.4 Capability-based workers

Do not permanently hard-code every turtle as one role.

Each turtle should advertise capabilities.

Example:

```lua
capabilities = {
    movement = true,
    mining = true,
    building = true,
    crafting = false,
    scanning = true,
    logistics = true,
    harvesting = true
}
```

The controller assigns work based on capabilities.

Some turtles will still have specialized equipment.

For example:

```text
scanner turtle
crafting turtle
standard mining turtle
builder turtle
logistics turtle
```

The scheduler should treat these as capability combinations instead of rigid identities whenever practical.

---

# 4. Turtle fleet roles

Support the following logical roles.

## 4.1 Miner

Responsibilities:

- search for underground resources
- excavate approved paths
- mine assigned resources
- return safely
- unload materials
- report observations
- maintain survey state

The current exploration design already introduces controller-owned finite sectors, route claims, material observations, resumable surveys, quotas, and safe return behavior.

Keep those behaviors.

## 4.2 Harvester

Handles renewable and surface resources such as:

- logs
- saplings
- crops
- bamboo
- sugar cane
- cactus
- wool
- flowers
- mushrooms
- snow
- clay
- sand
- gravel
- other registered resources

Harvesters should understand renewable versus destructive harvesting.

For renewable farms, they should replant whenever required.

## 4.3 Crafter

Handles recipes using crafting-enabled turtles or registered crafting machines.

Responsibilities:

- receive crafting requests
- reserve ingredients
- retrieve ingredients
- execute recipes
- deposit outputs
- report quantities produced
- return unused materials

## 4.4 Processor

Handles non-crafting transformations.

Examples:

- furnace
- blast furnace
- smoker
- stonecutter
- modded machines

Processing should use a generic provider interface where practical.

Example:

```lua
processor = {
    type = "furnace",
    inputs = {"minecraft:iron_ore"},
    outputs = {"minecraft:iron_ingot"}
}
```

## 4.5 Builder

Responsibilities:

- receive approved build region
- request required materials
- travel to project
- place blocks in safe dependency order
- report progress
- detect placement failures
- correct recoverable errors
- return or request resupply

## 4.6 Logistics turtle

Dedicated logistics turtles should move resources between:

- mines
- depots
- farms
- furnaces
- crafting stations
- central storage
- builder supply stations
- fuel stations

Miners should spend as much time mining as practical.

Builders should spend as much time building as practical.

Logistics workers should absorb routine transportation work.

## 4.7 Scout

Optional scout role.

Responsibilities:

- explore new territory
- record terrain
- detect obstacles
- find candidate resource areas
- locate trees or surface materials
- identify safe travel corridors

A scanner-equipped turtle would work especially well for this role.

---

# 5. Automatic turtle registration

A newly placed turtle should require as little setup as possible.

Desired workflow:

```text
fleet install
```

The turtle should then:

1. Locate the controller.
2. Register its computer ID.
3. Report turtle type.
4. Report peripherals.
5. Report equipped tools.
6. Report inventory state.
7. Report fuel.
8. Determine movement capability.
9. Determine crafting capability.
10. Determine scanner capability.
11. Download or verify current fleet software.
12. Receive configuration.
13. Enter the available worker pool.

Example registration:

```lua
{
    id = 27,
    protocolVersion = 4,

    capabilities = {
        move = true,
        mine = true,
        build = true,
        craft = false,
        scan = true,
        logistics = true
    },

    fuel = 16482,

    equipment = {
        left = "advanced_modem",
        right = "diamond_pickaxe"
    }
}
```

The existing design already calls for workers to advertise explicit exploration protocol support before receiving new exploration assignments.

Expand this into general fleet capability negotiation.

---

# 6. Schematic analyzer

When the user loads a schematic, parse the entire structure before starting construction.

Generate at least:

- total block count
- required block types
- block states
- facing/orientation
- tile entity data where supported
- placement coordinates
- support dependencies
- gravity-sensitive blocks
- attached blocks
- fluids
- redstone-sensitive components
- unsupported blocks
- required tools or special placement behavior

Example:

```text
Castle

Stone Bricks       18,421
Oak Planks          2,842
Oak Logs              922
Glass Panes          1,104
Iron Bars              448
Torches                 96
Oak Doors               32
Stone Stairs           612
```

Do not immediately turn this into individual worker jobs.

First create a project material plan.

---

# 7. Recursive material dependency planner

The planner should recursively expand manufactured items into their dependencies.

Example:

```text
64 pistons
    |
    +-- 192 planks
    |       |
    |       +-- logs
    |
    +-- 256 cobblestone
    |
    +-- 64 iron ingots
    |       |
    |       +-- iron ore
    |
    +-- 64 redstone
```

The planner should aggregate dependencies across the entire schematic.

If a schematic requires multiple recipes sharing ingredients, calculate the combined requirement.

The production service already connects shortages with acquisition, crafting, and smelting.

Extend this into a full dependency graph.

Suggested node types:

```text
RAW_RESOURCE
HARVESTED_RESOURCE
CRAFTED_RESOURCE
PROCESSED_RESOURCE
STORED_RESOURCE
BUILD_BLOCK
```

Example internal structure:

```lua
{
    item = "minecraft:piston",
    required = 64,
    available = 10,
    deficit = 54,

    recipe = {
        ingredients = {
            ["minecraft:oak_planks"] = 162,
            ["minecraft:cobblestone"] = 216,
            ["minecraft:iron_ingot"] = 54,
            ["minecraft:redstone"] = 54
        }
    }
}
```

---

# 8. Resource provider registry

Every resource should have one or more possible providers.

Example:

```lua
providers = {
    ["minecraft:iron_ore"] = {
        {
            type = "exploration",
            preferredY = 16
        }
    },

    ["minecraft:oak_log"] = {
        {
            type = "tree_farm",
            farm = "north_oak_farm"
        },
        {
            type = "wild_harvest"
        }
    },

    ["minecraft:glass"] = {
        {
            type = "smelting",
            input = "minecraft:sand"
        }
    },

    ["minecraft:stone_bricks"] = {
        {
            type = "crafting",
            recipe = "stone_bricks"
        }
    }
}
```

The planner should choose among available providers according to configured rules.

Possible criteria:

- available stock
- provider availability
- travel distance
- renewable source preference
- worker availability
- estimated cost
- fuel cost
- project priority

---

# 9. Mining and automatic exploration

Preserve the current exploration design.

The controller should divide configured search territory into finite sectors.

The current proposal uses deterministic 8 by 8 by 3 sectors and chooses promising sectors using known observations and stable distance ordering.

Important requirements:

- multiple miners may work on the same material
- miners must receive disjoint sector ownership
- routes must not conflict
- protected volumes must never be excavated
- every trip has a quota
- surveys must resume instead of restarting
- exhausted sectors should lead automatically to another sector
- observations should be remembered
- miners should return for low fuel
- miners should return when inventory fills
- miners should return after quota completion
- partial deliveries remain valid
- the parent request stays open until enough stock exists

The current design already requires several miners to share a material request and prevents double counting of outstanding demand.

Continue this approach.

---

# 10. Mining intelligence

Exploration should become smarter over time.

Store:

- observed ore positions
- searched sectors
- inaccessible sectors
- liquid hazards
- protected boundaries
- confirmed tunnels
- blocked paths
- material density
- successful mining locations
- exhausted resource clusters

Over time the controller should prefer areas with previous evidence of the desired material.

Do not treat scanner observations as permission to dig outside configured territory.

The current design already makes this distinction.

---

# 11. Automatic fuel management

Fuel should become a managed resource.

Every mission should calculate:

```text
current fuel
estimated outward fuel
estimated work fuel
estimated return fuel
required reserve
```

Example:

```text
Current fuel:            1,100
Mission estimate:        1,400
Required return reserve:   500

Result:
MISSION_DENIED_LOW_FUEL
```

The controller should then:

- dispatch fuel logistics
- route the worker to a fuel station
- assign a shorter job
- leave the worker idle

Miners must never knowingly begin jobs without enough fuel to satisfy the configured safety policy.

The current milestone requires fuel checks and safe return behavior but does not promise automatic fuel distribution to every miner.

Automatic fleet fuel logistics should be a later core milestone.

Supported fuel sources should be configurable.

Examples:

- coal
- charcoal
- lava
- other ComputerCraft fuels

Fuel inventory should appear in central resource planning.

---

# 12. Logistics network

Create a routing layer for item movement.

Define storage and stations as nodes.

Example:

```text
CENTRAL_STORAGE
IRON_MINE_DEPOT
TREE_FARM
FURNACE_BANK
CRAFTING_STATION
PROJECT_A_SUPPLY
FUEL_STATION
```

A logistics request should look conceptually like:

```lua
{
    item = "minecraft:iron_ingot",
    count = 128,
    from = "CENTRAL_STORAGE",
    to = "PROJECT_A_SUPPLY",
    priority = 70
}
```

Logistics workers should:

1. reserve inventory
2. reserve pickup
3. reserve destination capacity
4. travel
5. load
6. transfer
7. confirm actual transfer
8. report completion

Failed transfers should reconcile using observed inventory rather than assumptions.

---

# 13. Storage abstraction

The controller should have one logical inventory view even when items exist across multiple physical inventories.

Example:

```text
minecraft:stone

Central chest      12,442
Mine depot          3,821
Builder supply        768
Crafter input         128
Reserved            2,000
Available          15,159
```

Distinguish:

```text
physical stock
available stock
reserved stock
in transit
expected production
project demand
```

This prevents two jobs from spending the same items.

---

# 14. Continuous supply forecasting

Do not wait until a builder reaches zero inventory.

For every project calculate:

```text
required
stored
reserved
in transit
being mined
being harvested
being crafted
being processed
already placed
remaining deficit
```

Example:

```text
Stone required:       30,000
Already placed:        9,400
Storage:              12,400
In transit:            1,600
Mining assignments:    4,800

Remaining uncovered:
1,800
```

The controller should assign new mining work before builders exhaust their current supply.

This creates a continuous pipeline.

---

# 15. Parallel crafting

The current exploration milestone explicitly leaves parallel crafting for later work.

The full system should support multiple crafting workers.

Example:

```text
Need 8,000 stone bricks.

Crafter 1: 2,000
Crafter 2: 2,000
Crafter 3: 2,000
Crafter 4: 2,000
```

Use reservation accounting to prevent all four workers from claiming the same input stacks.

Craft jobs should be finite and measurable.

---

# 16. Processing network

Support multiple furnaces or modded processors.

Example:

```text
Iron required: 1,200

Furnace 1 capacity: 400
Furnace 2 capacity: 400
Furnace 3 capacity: 400
```

The scheduler should split production automatically.

Processing jobs should account for:

- input
- fuel if required
- output capacity
- machine availability
- processing time
- destination storage

---

# 17. Renewable resource harvesting

Implement renewable resource providers.

## Tree harvesting

Support:

- known tree farms
- automatic replanting
- sapling reserves
- tree detection
- trunk traversal
- leaf handling policy
- safe return

## Crop harvesting

Support:

- mature crop detection
- replanting
- seed reserve
- storage transfer

## Other farms

Design the provider API so future resources fit without rewriting the production scheduler.

Examples:

```text
wool farm
sugar cane
bamboo
cactus
mushrooms
flowers
mob drops
snow
cobblestone generator
stone generator
```

---

# 18. Builder fleet

Builders should support multiple workers on one project.

Do not have every builder independently walk the schematic.

Partition the project into owned work regions.

Possible partitioning methods:

- chunk-like volumes
- horizontal sections
- vertical layers
- rooms
- structural regions
- dependency-aware regions

Each region should have exclusive placement ownership.

Example:

```text
Builder 1
Region A

Builder 2
Region B

Builder 3
Region C
```

The controller should prevent builders from attempting to occupy the same cell simultaneously.

---

# 19. Placement dependency graph

Construction order matters.

Examples include:

- torches requiring support
- rails requiring support
- redstone dust requiring support
- doors requiring valid space
- beds requiring two positions
- buttons requiring attachment
- signs requiring support
- gravity blocks requiring support
- wall blocks requiring attachment
- plants requiring valid substrate

Convert schematic placements into dependency relationships.

Example:

```text
stone block
    |
    v
redstone dust
    |
    v
repeater
```

Builders should choose placements whose dependencies already exist.

Do not rely only on simple coordinate order.

---

# 20. Placement adapters

Create block-specific placement handlers.

Example:

```lua
placementHandlers = {
    ["minecraft:oak_stairs"] = placeDirectionalBlock,
    ["minecraft:oak_door"] = placeDoor,
    ["minecraft:torch"] = placeAttachedBlock,
    ["minecraft:chest"] = placeChest,
    ["minecraft:redstone_wire"] = placeRedstone
}
```

Unsupported blocks should produce a clear project warning rather than silent corruption.

---

# 21. Builder supply

Builders should not need to carry the entire project inventory.

Instead create supply batches.

Example:

```text
Builder 4 needs next:

Stone Bricks   512
Oak Stairs      64
Torches         16
Glass Panes     96
```

The logistics system prepares the batch.

The builder receives materials at:

- project supply station
- builder depot
- direct turtle transfer
- another configured method

Builders should request resupply before inventory becomes empty.

---

# 22. Verification

Completing the placement list should not automatically mean success.

The system should verify the built structure.

At minimum track:

```text
expected block
actual block
position
block state where supported
```

Results:

```text
CORRECT
MISSING
INCORRECT_BLOCK
INCORRECT_STATE
OBSTRUCTED
UNSUPPORTED
UNKNOWN
```

Recoverable defects should create repair jobs.

Example:

```text
Position:
142, 71, -318

Expected:
minecraft:oak_stairs[facing=east]

Observed:
minecraft:oak_stairs[facing=west]

Action:
REPLACE
```

---

# 23. Repair jobs

Verification defects should create normal schedulable work.

Repair workers should:

1. travel to defect
2. inspect location
3. remove wrong block if permitted
4. place correct block
5. verify
6. report result

Do not restart the entire build because one placement failed.

---

# 24. Worker state machine

Every turtle should expose a state.

Suggested states:

```text
STARTING
REGISTERING
IDLE
ASSIGNED
TRAVELING
WORKING
RETURNING
UNLOADING
WAITING
BLOCKED
LOW_FUEL
INVENTORY_FULL
OUT_OF_FUEL
NEEDS_TOOL
LOST
RECOVERING
PAUSED
ERROR
OFFLINE
```

The controller should maintain:

```text
last heartbeat
last known position
current assignment
fuel
inventory summary
current state
last error
software version
```

---

# 25. Automatic rescue and recovery

Where practical, one turtle should help another.

Examples:

## Low fuel rescue

```text
Miner 12
OUT_OF_FUEL
    |
    v
Controller identifies position
    |
    v
Logistics 4 receives fuel
    |
    v
Fuel delivered
    |
    v
Miner 12 returns
```

## Inventory recovery

If a worker becomes unrecoverable but its inventory can be reached, create a recovery job.

## Blocked return

If a safe return route is uncertain, do not blindly dig.

The current exploration design already specifies stopping in place when the return route becomes obstructed or uncertain.

Preserve that safety behavior.

---

# 26. Offline turtle handling

An offline turtle should retain:

- territory ownership
- build ownership
- inventory expectations
- movement reservation where needed
- assignment identity

Do not immediately give its physical region to another worker.

Use configurable timeout and operator recovery rules.

The existing exploration design already requires offline owners to retain claims during recovery testing.

---

# 27. Chunk loading

Large autonomous fleets require explicit handling of Minecraft chunk loading.

The current exploration design correctly states that turtles cannot be assumed to operate in unloaded terrain and that the software does not provide chunk loaders or modem relays.

Add a chunk-loading subsystem or compatibility layer later.

Possible integrations depend on the modpack.

The controller should know whether a mission requires chunks beyond guaranteed loaded territory.

Without a supported chunk-loading mechanism:

```text
MISSION_BLOCKED_UNLOADED_AREA
```

Do not pretend the turtle will continue operating outside loaded chunks.

---

# 28. Protected world regions

Maintain protected volumes for:

- turtle base
- controller
- storage
- cables
- farms
- crafting stations
- furnace stations
- project structures
- player-defined protected zones
- active turtle routes where required

The existing exploration design already requires automatic protection of project volumes, depots, stations, and configured infrastructure.

Extend this globally.

No mining worker should ever excavate a protected cell.

---

# 29. Traffic coordination

With many turtles, movement becomes a scheduling problem.

Maintain shared reservations for narrow paths.

Potential concepts:

```text
cell reservations
corridor reservations
intersection locks
one-way routes
waiting zones
depots
parking areas
```

A turtle should wait instead of digging through or colliding with another worker.

The exploration design already includes shared confirmed-clear passages and movement reservations.

Use the same mechanism for the full fleet.

---

# 30. Project priorities

Support multiple concurrent projects eventually.

Example:

```text
Project A
Castle
Priority 50

Project B
Rail Station
Priority 80
```

High-priority projects receive resources first, subject to reservations already committed to safe physical work.

Do not steal resources already physically committed if doing so breaks recovery guarantees.

---

# 31. Fleet scheduling

The scheduler should assign idle workers based on:

- worker capabilities
- project priority
- worker location
- fuel
- required equipment
- resource need
- travel cost
- current reservations
- chunk availability
- protected regions
- task dependencies

Example:

```text
15 idle turtles

Current demand:
Stone mining      6
Iron mining       3
Tree harvesting   2
Building           8
Logistics          4

Scheduler chooses the best valid allocation.
```

Workers should be reassigned as demand changes.

Example:

```text
18 miners
    |
Mining demand completed
    |
14 become builders
4 become logistics workers
```

where their equipment and capabilities allow.

---

# 32. Fleet dashboard

Provide a ComputerCraft monitor interface.

Suggested main project screen:

```text
========================================
            CASTLE PROJECT
========================================

Progress
██████████████████░░░░░░ 72%

Blocks
18,422 / 25,511

Resources

Stone Bricks
18,400 / 20,000

Oak Planks
2,420 / 2,842

Iron Bars
318 / 448

Workers

Mining       12
Harvesting    4
Crafting      3
Processing    3
Building      8
Logistics     4
Idle          2

Problems

Miner 07       LOW FUEL
Builder 03     BLOCKED
Furnace 02     OUTPUT FULL
```

Worker detail screen:

```text
MINER 07

State:
WORKING

Assignment:
IRON-00482

Sector:
18,4,-2

Quota:
34 / 64

Fuel:
7,442

Cargo:
9 / 16

Position:
821, 17, -104

Last heartbeat:
2 sec
```

---

# 33. Command interface

Possible controller commands:

```text
fleet status
fleet workers
fleet worker 27
fleet pause
fleet resume

project list
project status castle
project pause castle
project resume castle
project cancel castle

build castle.schem
build castle.schem --location here

resource iron
resource stone
resource oak_log

storage status

exploration status
exploration expand 128

worker return 27
worker recover 27
```

The exact syntax can evolve.

Keep commands consistent and scriptable.

---

# 34. Logging

Every significant action should have structured logs.

Example:

```text
[18:42:01] PROJECT castle created
[18:42:02] REQUIRE stone_bricks 20000
[18:42:02] SHORTAGE stone 17432
[18:42:03] ASSIGN miner07 sector 18,4,-2
[18:42:03] ASSIGN miner08 sector 19,4,-2
[18:44:18] DELIVERY miner07 stone 64
[18:44:21] STOCK stone 8932
[18:44:22] CRAFT crafter02 stone_bricks 256
```

Keep logs useful for debugging without flooding normal operator screens.

---

# 35. Network protocol

Messages should include:

```text
protocol version
message type
worker ID
assignment ID
sequence or receipt ID
payload
```

Validate every incoming message.

Never allow a worker message to invent an assignment absent from controller state.

The current exploration design already requires network validation and prevents worker reports from manufacturing exploration leases.

Preserve this model globally.

---

# 36. Duplicate message safety

Network operations should be idempotent where practical.

Example:

A worker reports:

```text
DELIVERY
assignment=482
receipt=99128
count=64
```

If the controller receives the same report twice:

```text
first message:
accepted

second message:
duplicate
ignored
```

Never credit the same physical delivery twice.

---

# 37. Checkpointing

Checkpoint before risky physical mutations.

Important checkpoints include:

- assignment accepted
- movement
- dig
- place
- inventory transfer
- unload
- crafting
- machine insertion
- machine extraction

The current exploration design already calls for journaling targets and inventory state around digs.

Extend that recovery discipline to builders and logistics.

---

# 38. Project completion

A project reaches COMPLETE only when:

1. all required placements have been attempted
2. verification finds no unresolved required blocks
3. active project worker assignments are finished
4. outstanding required logistics have reconciled
5. project inventory is reconciled
6. workers are safe or released
7. final project status has been persisted

Example:

```text
CASTLE

Status:
COMPLETE

Blocks:
25,511 / 25,511 verified

Workers:
0 active

Unresolved errors:
0

Completion time:
03:42:18
```

---

# 39. Failure conditions

Never silently loop forever.

Examples:

```text
RESOURCE_EXHAUSTED
SEARCH_ENVELOPE_EXHAUSTED
NO_VALID_ROUTE
INSUFFICIENT_FUEL
CHUNKS_NOT_LOADED
NO_COMPATIBLE_WORKER
MISSING_RECIPE
UNSUPPORTED_BLOCK
STORAGE_FULL
PROCESSOR_OFFLINE
PROTECTED_AREA_CONFLICT
BUILD_LOCATION_BLOCKED
WORKER_LOST
```

Each should produce:

- human-readable explanation
- affected project
- affected worker
- suggested corrective action where known

The exploration design already requires visible shortfalls when available search territory is exhausted.

---

# 40. Hands-off target

The final user experience should require as little intervention as practical.

Desired workflow:

```text
1. Place enough turtles and machines.
2. Register storage and infrastructure.
3. Load schematic.
4. Choose location.
5. Start project.
```

The system then performs:

```text
parse schematic
calculate materials
expand recipes
check storage
reserve existing stock
find shortages
mine resources
harvest resources
process materials
craft materials
move inventory
supply builders
construct structure
verify structure
repair defects
return workers
report completion
```

Routine project execution should not require manually telling individual turtles what to do.

---

# 41. Development milestones

Do not attempt everything in one implementation.

## Milestone 1: Autonomous exploration mining

Implement the current approved design:

- controller assigned search sectors
- several miners per material
- automatic sector selection
- discovery
- resumable surveys
- route excavation
- safe return
- quotas
- partial deliveries
- persistent ownership
- protected territory
- restart recovery

The existing acceptance target uses at least two miners finding materials without preconfigured deposit coordinates.

Keep this milestone focused.

## Milestone 2: Resource dependency graph

Add:

- recursive recipes
- aggregated project materials
- raw resource requirements
- provider registry

## Milestone 3: Fuel automation

Add:

- fuel forecasting
- fuel stations
- logistics refueling
- fuel rescue

## Milestone 4: Logistics fleet

Add:

- transport jobs
- inventory reservations
- pickup and delivery
- central stock abstraction

## Milestone 5: Renewable harvesting

Add:

- tree farms
- crops
- renewable resource providers

## Milestone 6: Parallel crafting and processing

Add:

- multiple crafters
- furnace pools
- machine pools
- production forecasting

## Milestone 7: Builder fleet

Add:

- multiple builders
- owned build regions
- project supply
- parallel placement

## Milestone 8: Placement dependency engine

Add:

- support dependencies
- directional blocks
- multi-block structures
- placement handlers

## Milestone 9: Verification and repair

Add:

- expected versus actual comparison
- defect jobs
- repair workers

## Milestone 10: Fleet intelligence

Add:

- dynamic worker roles
- optimized scheduling
- rescue missions
- improved routing
- multiple simultaneous projects

## Milestone 11: Chunk-loading integration

Add supported chunk-loading behavior based on the installed modpack.

---

# 42. Immediate implementation guidance

The current autonomous exploration design should still be implemented first.

Do not rewrite it into the entire fleet system immediately.

However, design its interfaces so later systems fit naturally.

Specifically, avoid interfaces such as:

```lua
assignMiner(...)
```

when a more general model fits:

```lua
assignJob(workerId, job)
```

Likewise, avoid treating every acquisition source as mining.

Prefer:

```text
resource request
    |
provider selection
    |
physical job
```

Possible provider types:

```text
exploration
farm
wild harvest
crafting
processing
storage
external machine
```

This keeps today's mining work compatible with tomorrow's full autonomous system.

---

# 43. Acceptance vision

The long-term acceptance test should be:

1. Start with central storage containing limited supplies.
2. Register a large turtle fleet.
3. Register farms, processors, storage, and fuel infrastructure.
4. Load a schematic containing raw, crafted, processed, directional, and renewable materials.
5. Do not manually identify ore deposits.
6. Do not manually assign workers.
7. Do not manually deliver building materials.
8. Start the project.
9. Allow miners to explore automatically.
10. Allow harvesters to obtain renewable materials.
11. Allow processors and crafters to satisfy dependencies.
12. Allow logistics workers to move supplies.
13. Allow several builders to construct concurrently.
14. Restart the controller during the project.
15. Restart one or more turtles during the project.
16. Allow the system to recover.
17. Verify the completed structure.
18. Repair recoverable placement errors.
19. Return the fleet to safe idle positions.
20. Report project completion.

The ideal final interaction is:

```text
> build castle.schem

Project created.
Analyzing schematic...

25,511 blocks
47 material types
18 raw resources
12 crafted resources
4 processed resources

Storage coverage: 38%

Workers available: 31

Project started.
```

Then the player walks away.

The project is finished when the controller reports:

```text
PROJECT COMPLETE

25,511 / 25,511 blocks verified
0 unresolved errors
31 workers accounted for
```

That is the target architecture.