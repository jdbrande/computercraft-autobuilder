# Inventory infrastructure protection

Version0.37 closes requirement28's missing spatial coverage for factory and
wired inventory endpoints. Use a controller `inventoryAreas` map keyed by wired
inventory name, with existing inclusive `{min,max}` boxes. Single containers use
identical corners; double chests and processors may need larger boxes. There is
no discovery API for remote inventory coordinates.

Reuse registered logistics, supply and fuel container geometry, normalized to
actual block cells. Include configured stock, furnace, Crafty and processor
endpoints plus saved unfinished contracts, transfer journals and held capacity
nodes. Explicit bounds may enlarge existing coverage but cannot contradict it.
Retain geometry independently of worker connectivity and own-project exclusions.

Accept old configurations, record missing names, and deny new destructive
assignments and mutation grants until every required endpoint is located. Keep
movement, safe returns, observation, retransmission and inventory reconciliation
available. Persist geometry in the existing controller startup checkpoint.
Reject moving/removing saved geometry while unfinished ownership exists. New
bounds cannot overlap retained destructive territory, routes or granted action
cells. This preserves already issued grants without introducing a revocation
protocol. Ordinary setup uses its existing idle transaction; direct settings
migration obeys the same saved-ownership checks.

Controller `setup factory` collects missing bounds before changing overrides.
Sort and bound registrations, deduplicate contained protection boxes, and retain
the exploration payload's explicit128-box failure rather than dropping coverage.

Implementation order:
1. Configuration/identity map, effective bounds, saved ownership and migration
   diagnostics with regressions.
2. Dispatch/mutation/exploration hooks and transactional setup prompts.
3. Focused/full suites, one final branch review and consolidated fixes.
4. Native protected furnace/Crafty/processor inventory overlap plus independent
   work, restart/offline ownership, sentinel contents and cleanup.
5. Permanent evidence, docs, integration; continue traffic/monitor/events/load
   and final combined fleet acceptance.
