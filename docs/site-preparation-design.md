# Automatic footprint preparation and leveling

Required scope: fleet-requirements45 and the clearing/builder ownership foundations
for44. The fixed pilot PREPARE_SITE path remains a compatibility path; general
schematics need their own bounded, immutable preparation contracts. This work is
required before claiming the full fleet complete.

## Intended geometry

The imported, transformed schematic is authoritative for every cell, including air.
Preserve already matching blocks/states. The normal foundation support surface is
one block below the schematic origin. This supports its entire footprint without
turning explicit interior air into fill or flattening intended schematic floors at
different elevations. A plan may explicitly describe different support elevations
per column through validated site metadata; transform these columns with the same
rotation/mirroring as the schematic. Never infer a higher foundation merely from
present terrain: a hill is an excavation requirement, not permission to move a build.

A surrounding one-block working margin and overhead clearance belong to the prepared
volume. Do not clear protected infrastructure to obtain that space. Plan geometry
is reconstructed from the immutable import hash; retain bounded cursors and region
summaries instead of copying a complete expanded volume into controller checkpoints.
Coordinates, dimensions, metadata and task/report sizes have explicit bounds.

Survey all footprint/workspace columns before their dependent preparation. Inspection
only workers descend from a reachable overhead stand until terrain or a required
boundary is observed. A hidden cell remains unknown until exposed and inspected;
never report inaccessible subsurface blocks as already surveyed. Optional scanner
evidence can inform the plan but never replaces inspection immediately before a
physical mutation. Unreachable survey coordinates remain actionable region blockers.

## Physical preparation

Partition the footprint into independent regions with explicit vertical envelopes
and an access halo. Existing durable task ownership, movement reservations and loaded
mission grants protect travel and work. Survey/excavation/fill jobs share the same
region identity and immutable preparation version. Pending regions cannot authorize
structural placement. Other nonoverlapping regions may continue when one is blocked.

Excavate high terrain and conflicting schematic/workspace cells from above. Inspect
before digging; keep matching schematic blocks, protected blocks, containers, turtles,
computers and registered infrastructure. Record exact coordinate, observed block,
reason and affected region on refusal. Use bounded work batches and home collection
to drain debris, retaining project/region progress between worker assignments. Never
discard cargo, steal reserved tool/fuel slots or clear a physical intent to make room.

Fill missing support columns with a stable available non-gravity material, ranked by
existing stock and known acquisition providers. The normal production graph requests
shortages, so exploration can supply fill. Explicit schematic material/state always
wins over generic fill. Verify the required support surface at every column and
reinspect nearby changed cells after excavation/fill. Falling blocks and fluids need
bounded stabilization and physical rechecks; a successful dig alone cannot certify
an area as prepared. Persistent changing terrain records a precise blocker while
unaffected regions proceed.

Use existing native dig/place inventory journals where their evidence is sufficient.
Extend their shared evidence rules when no-drop vegetation, fluids or falling-block
replacement require different outcomes; do not pretend requested effects occurred.
Every mutation has durable intent first, and ambiguous recovery retains ownership.

## Project integration and concurrency

Normal pipeline: survey, determine foundations, plan/reserve preparation, excavate,
fill, verify foundations, clear remaining volume, verify regions, build, verify,
repair defects, settle workers/inventories. Keep explicit survey/preparation status
and material demand visible. A builder can start only after its foundation, region
and access dependencies are verified. Matching partial structures remain intact.

The general scheduler uses suitable registered idle workers and durable regions;
subsequent workload scaling supplies role quotas, min/max bounds, rate/cost estimates
and bottleneck metrics for mining, hauling, crafting, clearing and building. It may
release only unowned work or physically settled workers. Optional turtle manufacturing
is not required to use the full registered fleet safely.

## Delivery and evidence

Implement in dependency order: immutable geometry/contracts; safe survey and shared
protection; journaled excavation/fill plus debris/supply; region verification and
normal project integration; parallel acceptance and dynamic role scaling. Each step
has failing boundary/restart/ownership cases before implementation. Do not describe
the whole requirement as complete until native uneven-terrain acceptance demonstrates
survey, leveling, fill acquisition, clearance, verification and construction without
manual site preparation, and scaling acceptance demonstrates automatic worker ramp-up
and drain-down for the required roles.

## Implemented batch boundary

`PREPARE_REGION` carries one immutable region identity, owned bounds, clearance
height and at most512 target cells. Clear cells may retain an exact schematic
block/state; fill cells use a supported stable cube and may accept existing stable
support. Verification batches inspect the same contracts without mutation. Progress
must count every inspected cell before completion and cannot regress or certify
uninspected coordinates. A completed batch may contain explicit defects; it is not
by itself a prepared-region certificate.

The existing construction executor handles approach, inspection and placement.
Preparation adds side inspection beneath retained floors, permission before each
mutation, bounded excavation attempts, and exact no-drop/falling-block recovery.
Reserved or unrelated inventory changes retain the journal. Known protected blocks
and controller-denied targets become coordinate-specific defects so other cells
continue. Workers exit the interior before releasing their task. Project batch
scheduling, material/debris flow and normal per-region construction gates now use
these receipts. Losing completed proof reopens a bounded verification census while
retaining physical ownership. Repairs start a fresh survey. Ordinary construction,
repair and mining require the same mutation grants; generated door halves reserve
both cells atomically. Exploration geometry includes registered infrastructure and
filters irrelevant distant boxes before enforcing its protection-payload bound.

External-flow containment and safe access to missing fully sealed foundations remain
unfinished. Multiworker native acceptance now has a permanent intermediate report.
Shared mutation protection now includes legacy clearing
and managed harvesting. Automatic final repair passes runtime regression tests. Eight-cell preparation batches currently favor bounded debris
handling over travel throughput; workload scaling can tune that batch boundary.

Generic support hidden beneath retained structure may use a fresh optional Geo Scanner
observation after all non-destructive inspection approaches fail. A positively
observed stable support name is sufficient for generic fill/verification; absent
scan entries never prove air, and name-only observations cannot certify exact
schematic states. Invalidate the scan cache before every such proof. Restore the
pickaxe after each scan and before resumed preparation; failed restoration blocks
the task without granting a support receipt. Missing hardware retains an explicit
inaccessible defect. Excavating/restoring access to a missing sealed cell remains
required work for inspection-only workers.

After every region drains its initial work, reconsider fluid-blocked regions once.
A distant slow region can remove inflow after an earlier region exhausted its three
local retries. Reuse the bounded region census; keep already verified regions and
non-fluid blockers unchanged. Fluid failures receive a fresh survey/work epoch and
another bounded local retry budget. Persist this one-time pass and its prior defect,
and preserve its marker across sidecar recovery. Continuous external inflow therefore
still stops after at most eight preparation attempts per affected region. This
reconsideration does not construct a boundary wall or certify unobserved terrain.

## Next access boundary

For a missing foundation beneath retained structure, plan a temporary inspection
shaft/tunnel within the same owned preparation region. The route must avoid every
non-air schematic cell; a matching floor is never permission to remove that floor.
Only ordinary removable terrain may open the route, with the existing mutation
grants and inventory journals. Plan explicit adjacent approach stands for horizontal
work beneath a retained ceiling. Keep each route bounded, contiguous and immutable.

Reuse preparation clear/fill tasks: open the access cells, inspect/fill the missing
support, restore temporary ground in reverse order, then repeat normal verification.
The access description must survive debris return, supply travel, worker exit and
reboot. Extend their shared overhead route helper to leave a recorded tunnel through
its shaft before ascending; a one-cell side exit does not suffice for an interior
foundation. Fuel admission must include that detour. No prepared-region receipt may
be issued while a temporary access cell still needs restoration. Protected terrain
or a footprint with no permissible bounded access retains an exact blocked report.

Required checks before implementation acceptance: an inspection-only turtle reaching
an interior missing foundation beneath a retained floor; fill and exact retained
structure verification; debris/full-inventory and material return through the tunnel;
partial excavation/placement checkpoints; blocked exit; protected access refusal;
and resumed ownership across both controller and worker restart. Native acceptance
must inspect the restored ground and retained structure independently.

The geometry helper now plans a shaft and horizontal route of at most128 cells
inside one region, reusing bounded pathfinding and rejecting every retained schematic
cell. This helper alone does not execute access. The worker contract still needs
explicit adjacent approach stands and route-aware supply/exit travel. Foundation
verification must occur while the tunnel is open; restoring it would otherwise make
the same inspection inaccessible again. Retain that fresh target receipt only within
the owned preparation epoch, require verified restoration before certification, and
discard it on a new survey/work epoch. Never promote a plan or an uncompleted access
sequence into foundation proof.

## Remaining mutation paths

The same adjacent-cell work grant must cover the legacy pilot and managed farms.
Authorize only immutable pilot waypoints or registered farm columns. Farm harvesting
may change its own crop/trunk cells while preserving the base of renewable columns;
its own farm registration must not prohibit that purpose. Other registered farms,
soil, infrastructure, offline occupants and owned work remain protected. The pilot
may clear its declared natural-terrain access above its own depot, but cannot use
that exception to remove the depot container or another worker's home.

Request mutation permission after inspection and before persisting a new physical
intent. Release a grant after the journal reconciles. Existing physical intents
retain their reconciliation path across reboots; an ordinary movement grant cannot
authorize digging or replanting. Test delayed/denied permission, occupied farm cells,
foreign sites, shared farm ownership and post-effect restart before expanding native
acceptance. Reuse the current work reservation and task contract boundaries.

## Automatic final repair

A failed final verification after construction starts at most three automatic repair
rounds. Each round persists a bounded defect summary with its new preparation
generation, repeats the survey/preparation gate and runs the existing repair engine.
Matching blocks remain in place. Restarting either runtime resumes that round and
does not reset the attempt count. Recurring defects stop with their exact final
report and a visible retry-limit explanation. Explicit `build verify` remains a
read-only inspection; an explicit new repair request can begin a fresh retry budget.

Fill selection compares unreserved stock with the survey's bounded possible fill
volume and checks eligible acquisition workers. A small unreplenishable debris pile
must not strand the project when another suitable fill is replenishable. This bound
only chooses the material: physical inspection still determines supply quantities.

## Prerequisite for multiple construction workers

The current supply chest is global, but home-return buffers belong to individual
worker depots. Pointing several workers at one depot would leave returning idle
workers blocking that physical stand. Add optional registered `supplyStations`,
keyed by worker ID, with inventory, depot stand and transfer side. Each worker keeps
its local supply configuration; controller grants must match it before transfer.
Defaults retain the existing single-chest installation.

Use the current supply journal and receipt identity. Persist the chosen endpoint
with each batch and reject configuration changes while it is owned. Validate that
station inventories cannot alias storage, fuel, crafting or private return buffers.
Protect their actual containers and stands from excavation. Keep the existing one
active supply transfer while builders work independently; measure this ceiling in
scaling acceptance before replacing the existing supply/storage coordination.

This prerequisite was identified while checking multiworker site acceptance. It is
part of Task45 and sections18/21/44, not a substitute for the remaining fluid and
sealed-foundation preparation work.

Multiworker route prerequisite: confirmed worker-occupancy denials trigger bounded
256-node pathfinding around observed occupied cells. The route survives worker
restart; every step still requires normal reservations, coverage, protection and
fuel. At most16 excluded traffic cells are retained per waypoint. Failure to find
a bounded route remains visible and does not permit digging or entering a denied
cell. This does not establish arbitrary-maze routing or unlimited deadlock recovery.

Preparation retry policy: a failed final region verification may schedule up to
three fresh read-only surveys and preparation passes. Keep its prior defect summary
and retry count in the region sidecar and active ownership metadata. Re-survey only
after every prior physical owner has completed and its debris has settled. Use a
new work epoch, keep the immutable schematic identity, and never certify that
region or schedule dependent construction between attempts. Other regions continue.
A checkpoint failure or ambiguous physical action remains owned and cannot be
converted into a completed task to unlock a retry. Exhausted retries leave the
exact final defects visible. This policy is separate from final structural repair.

Fluid execution increment: when an excavation report finds water/lava, use the
existing fill material and journaled placement to seal fluid cells across that
region's clearance volume, without altering air or non-fluid blocks. Finish that
seal pass before clearing the temporary solids. This drains finite pockets whose
sources lie inside the covered region and recovers the temporary material through
ordinary debris collection. Fresh verification and the bounded re-survey policy
handle later changes; persistent external inflow stays a precise blocker. Coordinated
containment across fluid regions and externally fed boundaries remains required
before general fluid preparation can be accepted.
