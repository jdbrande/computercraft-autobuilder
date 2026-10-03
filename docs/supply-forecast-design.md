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

Workers calculate a bounded upcoming material need from their current immutable
BUILD/REPAIR region, remaining cursor and unreserved inventory. At a safe action
boundary, positive cargo at or below one quarter of the configured batch triggers
the existing resupply journal for the remaining shortage. The worker retains its
last items while normal supply handling obtains replacements. Zero cargo still
uses inspection-driven missing-material handling. No separate forecast reservation
or transfer protocol is added. Existing batches, factory exclusion, production
requests, tombstones and measured receipts remain authoritative.
Preparation fill stays inspection-driven because suitable ground can eliminate
its apparent demand. VERIFY/CLEAR, paused work and in-flight placement/navigation
cannot trigger early resupply. Finite concurrent requests retain the existing
shared-stock acquisition behavior and duplicate/restart guarantees.

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

Implementation detail: the view allocates unreserved shared stock once in stable
project-name order. This is a read-only estimate, not a ledger reservation or
scheduler priority. Per-item correct totals describe the current construction or
verification generation. During a new verification pass the confirmed count grows
again as cells are revisited. Offered supply staging remains explicitly uncertain
until its actual transfer is reflected in cargo/receipts; its original grant amount
is never added again to fresh worker cargo. Legacy and offline evidence is marked
unknown. These conservative gaps do not create production requests from the view.

Ruling after tracing supply/factory exclusion: a separate prefetch request that
holds staging while placement continues can block the factory operation needed to
fill it. Early top-up therefore enters the existing resupply flow immediately at
a safe boundary. This starts acquisition before zero with one durable owner and
requires no new network message. Cost: that worker waits during replenishment;
overlapping initial production and sustained placement remains the next pipeline
change rather than an unsupported claim in this milestone.
