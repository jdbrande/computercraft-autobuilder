# Resource dependency graph and providers

Implements fleet requirements 7–8 and milestone 2, as the foundation for fuel,
reservation and concurrent production work. Preserve the existing controller,
queues, recipe registry and hardware executors.

The planner already recursively expands recipes, shares surplus, deducts stock and
reserves fuel. Extend that result with item-keyed dependency nodes and explicit
operation dependencies instead of introducing a second scheduler. Quantities in
the graph are forecasts, never credited physical stock. Keep legacy `raw`,
`missing`, `operations`, `available` and `fuel` outputs usable by saved requests.

A provider registry derives candidates from current recipe, mining and configured
farm definitions. Stock satisfies demand first; otherwise configured provider-type
preferences and compatible online workers select among executable candidates.
Default order preserves legacy recipe/mining/farm behavior. When all candidates
lack workers, keep the best configured candidate visible with an actionable wait
reason; do not invent a source. Candidate IDs are stable (type plus item/farm
index); copy farm geometry into a physical assignment before effects.

For active acquisition, the saved trip/group or harvest job wins over later
configuration preferences. Re-evaluate an unavailable candidate only when no
physical assignment owns work. This permits newly connected farms/workers without
abandoning offline owners. Raw mining targets keep the existing measured-stock
and physical-return reconciliation rules.

Graph nodes aggregate required quantities across roots and recipes, original
physical stock (including fuel held for the separately counted reserve demand), deficit, planned production, raw shortage, provider and input edges.
Each operation identifies earlier operations producing its inputs. Preserve
batch surplus accounting; do not blindly coalesce operations across consumers.
Validate recipe cycles, depth, yields, ingredient counts, expanded count limits,
provider preference arrays and unknown provider types before scheduling work.

Expose graph/provider information through a read-only `resource ITEM` command
and production status. Tests use existing hardware/runtime fixtures. Acceptance
includes shared intermediate requirements, stocked final/intermediate items,
missing providers, malformed/cyclic recipes, provider preference/fallback,
restarts retaining existing ownership and the existing complete construction
chain. Live testing will reuse the real fleet where changed dispatch paths warrant
it; do not label a pure planning test as physical acceptance.

This milestone does not remove the exclusive factory barrier. Its graph/provider
outputs become the inputs for the subsequent reservation and fuel milestones.
