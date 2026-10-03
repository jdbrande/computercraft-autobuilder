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
