# Continuous material forecasts and early replenishment

Required scope: fleet requirements14 and21, extending the existing ledger,
production requests and builder supply journals. This milestone adds accurate
project visibility and acquisition before an active builder runs out. Starting
construction before its initial full material preparation is a separate dependent
pipeline change; it is not declared complete by this milestone.

## Chosen approach

Use the existing physical inventory ledger for stock, reservation and transit
categories. Derive project production categories from its linked finite jobs and
requests. Add optional bounded per-item correct-position totals to compact worker
reports and retain them when block payloads are retired. Totals mean observed
correct material positions, including matching pre-existing blocks; they never
mean newly manufactured or delivered items. Upper door halves and air consume no
additional item. Legacy reports without totals remain explicitly incomplete.

A project forecast shows required, observed correct, shared physical stock,
reserved stock, transit, worker-held stock, active mining/harvesting/crafting/
processing estimates and uncovered demand. Shared stock is labeled shared and is
not promised independently to every project. Reserved/transit/expected categories
are disjoint in deficit arithmetic; production expectations are never stock.
Paused/offline owners retain their claims and cannot authorize new work.

Workers publish a bounded upcoming material need from their current immutable
BUILD/REPAIR region, remaining cursor and unreserved inventory. This forecast does
not claim a supply chest, interrupt placement, or transfer items. The controller
aggregates eligible needs and requests finite replacement stock through existing
production before the workers reach zero. Requests are idempotent while active;
completed-batch tombstones and ordinary actual supply receipts remain authoritative.
Existing station leases, factory exclusion and measured resupply stay unchanged.
Preparation fill remains inspection-driven because existing suitable ground can
eliminate its apparent demand. VERIFY/CLEAR and paused work cannot create demand.

Alternatives rejected: a second inventory ledger would duplicate ownership; a
whole-project reserved stock promise would require changing all current consumers;
a new courier protocol would duplicate existing logistics. Reusing finite production
requests keeps failures and recovery inside existing boundaries.

## Evidence and limits

Test item totals against actual builder reports, malformed/regressing counters,
duplicate packets, restart, payload retirement and mixed blocks/door halves. Test
lookahead with positive remaining cargo, reserved/NBT slots, paused/offline owners,
shared demand, active requests, completed work and missing telemetry. An actual
runtime must consume limited initial stock while replacement mining/production
starts before zero, then finish and reconcile inventory across restart. Native
acceptance is useful for the same early-acquisition boundary. One final review and
consolidated regression pass precede complete tests and integration.

Forecasts are bounded estimates. Existing correctly built regions can reduce actual
consumption; finite in-flight production may finish with surplus, which remains
physical stock. No forecast licenses excavation or changes durable ownership.
