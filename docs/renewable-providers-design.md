# Renewable provider coverage and reserves

Requirement17 already has journaled tree/crop/column harvesting, safe return,
replanting and measured deposits. Complete its extension and reserve policy using
the same actor and provider scheduler. Do not add another physical task engine.

Move managed plant definitions into a bounded plain-data registry. Include current
wheat/columns/three simple tree types and add ordinary carrot, potato and beetroot
crops with their actual maturity ages and planting items. Optional registered crop
or column definitions describe exact block/output/seed/maturity/substrate behavior;
the selected definition is copied into the durable farm task. A controller restart
or later registry edit cannot reinterpret an existing harvest journal. Definitions
cannot supply executable callbacks or arbitrary turtle/peripheral methods.

A farm may retain an explicit seed/sapling count, at least one item per configured
site by default. Reserve retention must work when harvested output is also the
planting item: only actual unreserved surplus reaches demand or forecasts. Require a
planting item before destructive harvest, and retain durable replant intent across
interruption. Existing protected areas, finite fuel, bounded columns, branch refusal
and leaf handling remain unchanged. Use the selected definition for fuel budgets so
registered columns receive the same safe route estimate as built-in columns.

Provider availability must include known worker health, while existing owners keep
their claims. An unhealthy preferred farm worker must not prevent an eligible
alternative source from satisfying unowned demand.

Other resource examples fit existing contracts: automatic wool/mob/snow/generator
machinery can deposit into registered stock or logistics-node inventories, and
powered processing uses registered processors. The fleet observes actual collected
items; it does not pretend a Lua turtle has a generic shearing or arbitrary machine
API. Document exact supported actor contracts and external infrastructure instead
of advertising unsupported native actions.

Tests exercise mature/immature ages, seed-as-output reserves, partial deposits,
interrupted replanting, retained adapter identity, registered columns, provider
health/fallback and exact harvest-to-storage evidence. Native acceptance uses real
managed crops and checks replanting, reserves, stored surplus and safe return.
One final review/consolidated correction pass and full gates precede integration.
