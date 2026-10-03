# Demand-driven fleet allocation

Required next milestone: fleet-requirements44. Preparation45 supplies bounded,
independent clearing/building regions and durable access/containment gates. Keep
existing job ownership authoritative; scaling only governs new dispatch and the
number of bounded unassigned batches exposed by producers.

## Allocation and safe scale-down

Recompute useful worker counts for mining, hauling, crafting, clearing and building
from outstanding physical work, independent ready jobs, eligible equipment, finite
fuel, stock/capacity availability and measured delivery/completion rates. Apply
configurable per-role minimum/maximum counts. Minimums apply only while useful work
exists; drained work has a desired count of zero. A maximum reduction never revokes
an existing physical owner, inventory claim, pending action or return obligation.
Workers finish and settle before returning to the shared idle pool.

Estimate worker time from remaining units and observed throughput, including travel
and supply delays. Before enough observations exist, use conservative bounded
estimates: mining route length and observed yield, preparation volume and surveyed
obstructions, structural blocks/dependencies, recipe batches and transport distance.
Do not count stock already owned/in transit twice. Retain measured zero-yield mining
trips as evidence of search cost rather than inventing successful delivery.

Allocate finite available capacity across demanded roles. Prefer specialized idle
workers before consuming a worker needed by another role. Give supply and processing
bottlenecks enough capacity to feed construction. Respect existing global staging,
private machine, traffic, chunk, equipment and stock gates; more turtles cannot solve
an unavailable furnace, disconnected chest or exhausted protected search envelope.
Report that limiting resource rather than manufacturing demand or ownership.

Use all suitable registered idle workers when they can improve useful throughput,
up to configured maxima. No automatic turtle manufacturing is assumed. Prioritize
rescue, fuel and durable home/debris settlement independently of ordinary quotas so
scale-down cannot prevent an owned worker from finishing safely.

## Integration boundaries

- Shared controller allocation state and configuration provide target/active/idle
  counts, queue/work estimates, throughput, limiting conditions and recent decisions.
- Mining dispatch applies the target to legacy and exploration assignments. Split
  remaining acquisition quotas among the workers actually admitted by scaling.
- Workflow dispatch applies role targets only to new ownership. Retransmissions,
  recovered owners, paused/offline tasks and durable leases keep their identities.
- Recheck admission at the final ownership checkpoint, including chunk operations
  that yield. Never grant two jobs from a stale idle-worker or quota observation.
- Replace fixed preparation/structural queue windows with bounded demand-driven
  windows. Retain a hard memory limit and independent-region/dependency checks.
- Private crafting and managed transport producers expose useful parallel batches
  within the same allocation, without acquiring unnecessary stock for excess work.

Completion timestamps must measure physical delivery/completion. Record samples
before job retirement prunes receipts, and persist sample consumption with counters
so restarts cannot double-count a task. Bound retained metrics and decision history;
they are diagnostics, not another source of ownership truth.

## Acceptance

Add tests for validated bounds, small versus heavy demand, measured yield/travel/
delivery effects, mixed capabilities, idle reuse, competing roles, storage bottlenecks,
minimum/maximum changes, failed checkpoints and controller/worker restart. Prove
one-to-many ramp-up and drain-to-idle without cancelling or duplicating physical work.
Keep current exploration, supply, crafting, preparation and settlement regressions.

Run a native mixed-material job large enough for several miners, clearers and
builders to contribute automatically. Record assignments over time, independent
work regions, actual deliveries/placements, bottlenecks and final home/stock/lease
settlement. Operator-provided terrain/resources and loaded areas must remain explicit
fixture assumptions. After one whole-branch review/fix pass and full checks,
integrate and continue the remaining forecasting, provider, placement, recovery,
health/interface and larger-scale requirements.

## Initial estimate policy

The initial allocator uses a two-minute planning window. Bootstrap costs are eight
seconds per mined item, four per hauled item, one per crafted item, two per prepared
cell and three per structural cell. Mining adds the amortized round-trip distance
of eligible workers' exit routes. These conservative estimates are replaced by the
last32 physical completion samples per role; zero-yield trips contribute elapsed
time but no items. Cumulative counts remain available for diagnostics. A restored
old job without an assignment timestamp is excluded from rate samples.

Desired counts are bounded by useful independent ready work, capable idle/active
workers and configured0..128 role limits. They are estimates; final dispatch retains
all existing material, station, tool, fuel, region and route checks. Home, fuel and
rescue operations and temporary-access restoration bypass ordinary scale-down so
changing a role maximum cannot strand an existing physical obligation.
