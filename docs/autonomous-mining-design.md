# Autonomous material gathering for schematic builds

Status: milestone 1 design, confirmed by the supplied fleet requirements on
2026-10-02. Implementation has not started.

The [fleet requirements](fleet-requirements.md) define the complete product and
milestone order. This document specifies autonomous exploration, the first
milestone requested in sections 41 and 42 of those requirements.

## Outcome and scope

The user wants to load a schematic and have a fleet discover its raw materials,
craft the required blocks, and construct the result. Miners must explore outward
automatically instead of requiring a marked deposit for every material. The user
approved starting with automatic exploration by several miners feeding the existing
crafting and building pipeline.

This milestone delivers that first loop for registered mining materials and
supported schematics. It includes several miners sharing a request for the same
material. Parallel crafting, wild tree harvesting, broader placement support, and
large fleet throughput improvements are subsequent work. Existing managed farms
and manually stocked items remain valid sources for non-mining ingredients.

The final fleet must run acquisition, processing, crafting, transport and building
concurrently wherever dependencies permit. Keeping the current factory/storage
barrier in this milestone is a temporary compatibility constraint. Later inventory
reservations and production work will replace that barrier; it is not the target
fleet architecture. Automatic fuel distribution, rescue, broader harvesting,
capability negotiation and supported chunk-loading integration remain required
parts of the full product, in the user's stated milestone order.

Acceptance requires a small schematic to reach verified completion after at least
two miners discover and supply its ingredients without configured deposit
coordinates. A simulation must prove the behavior across restarts; a separate
in-game trial establishes live acceptance. Neither implies arbitrary schematics
or every resource can be completed unattended.

## Existing behavior

- `core/production_service.lua` computes shortages and connects acquisition to
  crafting and smelting. `build auto NAME` already runs preparation and construction.
- `core/jobs.lua` assigns one physical miner to a material request. Independent
  materials can run concurrently in disjoint configured boxes.
- `resources/miner.lua` searches a fixed box, preserves a return trail, unloads at
  its depot, and refuels. Travel outside that box assumes a cleared corridor.
- `resources/scanner.lua` supports Geo Scanner observations and tool restoration.
  The miner also has an adjacent-inspection fallback.
- `core/workflows.lua` coordinates movement and prevents factory work from
  overlapping mining/storage mutations. Preserve that barrier in this milestone.
- The completed small pilot and saved jobs must survive an update unchanged.

The design extends these components rather than introducing another scheduler,
database, network library, or generic agent framework.

Keep the boundary resource request -> provider -> physical job. Record
`provider='exploration'` on the new acquisition group. Reuse capability-based
assignment and the existing job/worker identifiers; do not permanently bind a
turtle to the miner role or implement a speculative provider framework now.
The existing recipe planner, furnace pool, farms, builder regions and verification
are starting points for later milestones, not systems to discard and recreate.

## Approach

Use controller-assigned, finite search sectors within one exploration envelope.
The controller chooses sectors automatically, shares discoveries, and assigns
exclusive ownership. Each trip produces a measured partial result. The material
request remains open until enough stock is physically available.

Independent roaming by each turtle would require an additional distributed claim
and accounting system. Requiring a Geo Scanner would simplify discovery but exclude
the existing inspection fallback. Controller-assigned sectors reuse current
ownership and recovery behavior while supporting either discovery method.

## Setup and operating limits

Add an exploration option to the miner setup wizard and a controller exploration
setup. Existing fixed-area setup remains available. Exploration is disabled on
upgrade until configured; installation alone never starts movement.

The operator supplies the base position, known position/heading and unloading
station for each miner, a base protection box, and an outer search envelope. This
is one operating boundary, not a list of mines or known deposits. Propose an
initial horizontal radius of 64 blocks and heights from base Y minus 16 through
base Y plus 16, clipped to the configured dimension limits. Setup displays the
actual coordinates before saving. These values are adjustable and are not claims
about where a particular resource exists.

Keep the configured envelope inside loaded terrain and communication coverage.
This milestone does not install a chunk loader, keep an unloaded turtle running,
cross dimensions, or create modem relays. Setup records the operator's operating
boundary; the software cannot prove all those chunks will remain loaded. A lost
worker retains its work and territory until reconciled.

Miners retain their pickaxe, modem, reserved fuel/tool slots, and wired deposit
chests. An optional scanner accelerates discovery; ordinary inspection can search
more slowly. Startup fuel must be supplied. Already-mined coal can replenish a
configured fuel source through existing logistics, but this milestone does not
promise automatic fuel distribution to every miner's station.

Automatically protect imported project volumes, registered depot/station positions,
and their necessary clearance, in addition to configured restricted areas and the
base protection box. Peripheral names do not reveal physical coordinates: setup
must include unlocated cables, chests, farms and machines in protected boxes.
Planning a new project that overlaps owned exploration work must block until the
miner has returned and the conflicting work is retired.

## Search and travel

Partition the envelope into deterministic 8 by 8 by 3 sectors, clipped at edges.
Prefer sectors with a recorded observation of the requested material. Otherwise
search outward in stable distance order, using the material registry's suggested
height as a preference within the allowed envelope. Equal choices use stable
coordinate order. A height preference is not evidence that ore is present.

Assign only reachable candidates within the existing pathfinding budget. A trip
contains the sector, its entry, an explicit bounded access route, and a saved
quantity quota. Access routes may excavate allowed natural blocks inside the
exploration envelope. They may use declared cleared exits from protected depots,
but may never excavate protected cells. This removes the current requirement for
a player-cleared route to each individual mine.

Save the sector and access-route excavation claims before dispatch. Never overlap
another miner's owned search sector or uncompleted excavation route. Previously
confirmed clear passages can be shared using existing cell movement reservations;
an occupied passage waits without digging the occupying turtle. Route length must
fit the available round-trip fuel budget, including the existing reserve, and
cannot exceed `maxTravelDistance`. Route messages are bounded by that same limit.

If no route fits the path budget, try another candidate and record the reason.
Liquids, protected blocks, unsupported terrain, and blocked return paths produce
visible outcomes. They never authorize widening a route or mining through the
base. An obstruction during outward exploration triggers a safe return when the
recorded trail remains usable; an obstructed or uncertain return stops in place.

Record observed material locations, inspected survey progress, and unresolved
obstacles. Scanner results outside permitted territory are observations only, not
excavation authorization. Every target is inspected again before digging.
Finishing a survey means the selected scan/inspection pattern was attempted; it
does not prove that the whole sector is empty. Progress is material-specific so
searching for stone does not mark that area searched for sand.

Return and unload when the quota is met, cargo is nearly full, return fuel is
reached, the finite survey ends, or the project pauses. Persist the cursor so a
later trip can continue after an inventory/fuel return. Do not repeatedly restart
an exhausted survey. When every candidate is searched or inaccessible, show the
shortfall and stop assigning work until the operator extends the envelope or
resolves a reported obstacle.

## Material requests and trip accounting

Introduce an exploration acquisition group referenced by the production request
for each missing mining material. It owns the desired live-stock target and a list
of finite physical trip jobs. Keep this separate from legacy linear supplement
chains. Only physical trip jobs own workers, territory, and movement reservations.

Start with a maximum quota of 64 requested items per trip. Distribute remaining
demand among eligible idle miners in worker-ID order. Before assigning, refresh
stock and subtract undelivered quotas already owned by outstanding trips. If a
stock refresh fails, issue no new quota. Deposited quantities are counted through
the refreshed stock snapshot; held items and unacknowledged assignments remain
outstanding rather than becoming additional stock.

At the depot, a trip reports a terminal reason and cumulative delivered count:
quota reached, survey exhausted, cargo return, fuel return, or paused return.
Zero and partial deliveries are valid terminal trip results. They do not complete
the acquisition group. Actual inventory transfers determine delivered amounts;
scan observations and anticipated drops never do. Incidental drops join ordinary
stock and reduce later shortages on refresh.

Progress is monotonic and tied to the original worker, group, trip and quota.
Duplicate reports and lost acknowledgements must not double-credit stock or create
another owner. Reservations remain until physical return and transfer recovery are
confirmed. A group is ready only when refreshed stock meets its target and all
owned trips have returned and unloaded. The factory then proceeds through the
existing crafting, smelting, supply, building and verification pipeline.

Pausing prevents new assignments and asks owned explorers to return safely without
another outward dig. Resume continues remaining demand and saved survey cursors.
Disabled exploration prevents new trips but must still allow an already-owned
trip to reconcile and return under its saved permissions.

## Persistence and compatibility

Extend existing checkpoints with acquisition groups, sector survey records, bounded
material observations and trip geometry. Keep one exploration record per sector;
retain at most 64 material observations per sector, with deterministic replacement
of old unclaimed observations. Never discard active claims or return trails.
Cap the configured envelope at 4096 sectors and refuse a larger configuration with
an actionable message. Anchor sector IDs to the original base grid so expanding
the envelope preserves previous observations and survey progress. Changing that
grid requires all trips to finish and an explicit new exploration configuration.
Retire acknowledged trip history using the existing receipt
approach; keep group references until their production request is retired.

Extend registration with an explicit exploration protocol capability. Assign
exploration only to workers advertising it. Exploration assignment/progress fields
must be validated and copied in the existing network message boundary, including
route bounds, quota, result reason, and bounded observations. Existing miners keep
their original fixed-box semantics. An old worker never receives a new trip type.

Save assignment geometry before sending it, and save validated worker ownership
before any physical effect. A saved trip uses its original geometry after restart;
configuration changes cannot silently widen it. Permission changes that invalidate
the saved route block new outward work and require reconciliation of the return.
Backup recovery must match the original persisted assignment; a worker's report
cannot manufacture an exploration lease absent from recoverable controller state.

Exploration digging must journal the target, inspected block and relevant inventory
before mutation, then reconcile block/inventory observations after restart. Reuse
the existing checkpoint and site-clearing recovery patterns. Never blindly repeat
an uncertain dig or credit unexplained inventory changes. Preserve the current
movement and deposit recovery mechanisms, including scanner tool restoration.

## Integration surface

Keep geometry/search bookkeeping in a focused exploration module under `resources`.
Extend `core/jobs.lua` and `core/mining_service.lua` for groups, leases, partial
trip results and retirement; extend `resources/miner.lua` for saved trip geometry,
route excavation and resumable surveys. Update configuration, setup, registration
and mining message validation together.

Connect acquisition groups in `core/production_service.lua`. Update project
pause/resume and protected-volume coordination in `blueprint/projects.lua`.
Preserve factory/storage exclusion in `core/workflows.lua`; include exploration
trips wherever the existing code checks physical miners. Controller material status
must show total stock/target, each assigned miner, search progress and blocked
reasons. Document exact in-game setup and update the generated release assets only
after implementation verification.

## Verification and acceptance

Extend the current Lua simulator and runtime integration tests; add no framework.
The essential checks are:

1. Two miners receive disjoint search/route claims for one material and both deliver
   toward one target without over-allocating outstanding demand.
2. An empty first sector leads to another sector automatically. A partial trip
   finishes at its depot while the parent material request remains incomplete.
3. Full cargo and low fuel preserve the cursor, return and unload; replenishment
   allows another trip. An unavailable fuel source reports a stop.
4. Protected base/project cells, liquids, outside-envelope routes, conflicting
   excavation claims, invalid messages and unsupported workers never authorize digs.
5. Restarts around assignment, dig, movement, deposit and completion, with duplicate
   or dropped packets, preserve ownership and credit each delivery once. Offline
   owners retain claims. Saved trips survive compatible configuration changes.
6. Pause returns explorers and prevents fresh work. Exhaustion reports a material
   shortfall; expanding the envelope adds candidates without repeating known work.
7. The full runtime fixture starts with raw ingredients in undisclosed world cells,
   uses multiple explorers, crafts/smelts, supplies a builder, and verifies a small
   supported schematic. No completed-block stock is preloaded. Repeat using the
   inspection fallback and exercise finite movement fuel.

Run the existing Lua and Python suites to protect fixed-area mining, the completed
pilot, installer behavior, crafting and construction. Then perform a live trial
with two explorers, one crafter, furnace storage and one builder in a loaded test
area. The live checklist includes automatic second-sector selection, pause/return,
a reboot, measured deliveries and verified construction. Keep simulation results
and live acceptance results separate in the validation record.
