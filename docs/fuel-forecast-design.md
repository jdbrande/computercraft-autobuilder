# Mission fuel forecasts

Complete the remaining requirement 11 work using existing fuel stations, rescue,
task queues and `resources/fuel.lua`. Fuel remains a physical quantity measured by
the turtle. Forecasts neither create inventory nor authorize unsafe movement.

## Budgets and admission

A shared `resources/fuel_budget.lua` computes `current`, `outward`, `work`,
`returning`, `reserve`, `required`, `shortfall` and `allowed`, plus a scope label.
Use the existing `Fuel.budget` arithmetic and known task geometry. Stationary
crafting needs zero movement fuel. Unknown moving-worker pose or missing route
geometry is an explicit unavailable budget, never zero cost.

Construction retains its current conservative largest next-target excursion,
including overhead travel, placement approach, access shafts, return and reserve.
Extract that calculation so worker enforcement and controller presentation share
it. A multi-target job may refuel between excursions; do not demand enough fuel
for an arbitrarily large project before its first placement. Mining similarly
budgets a bounded outbound/search/return excursion through its existing geometry
and recorded return trail. Renewables use their configured overhead height and
next site; hauling includes pickup, one cargo delivery and return; rescue and
home/refuel missions include their full bounded travel. Unknown detours still
use navigation's live reserve checks.

Publish an optional validated budget in telemetry for the worker's current task.
Legacy telemetry remains accepted. Reject malformed numbers, inconsistent sums,
task mismatches and budgets inconsistent with reported current fuel. Copy only
known fields. Station forecasts use fresh online telemetry and controller-owned
jobs; untrusted reports cannot manufacture jobs or source fuel.

When automatic fuel is enabled, ordinary new dispatch must pass the budget at the
shared final admission boundary, including after yielding coverage calls. Low
fuel keeps the work queued and lets another ready worker take it. Managed refuel,
rescue and safe return keep their existing recovery admission paths; an insufficient
budget never revokes existing ownership or consumes arbitrary building cargo.

## Forecast and replenishment

The fuel view lists each current or next compatible mission and its components.
For idle workers, select one ready compatible queued job deterministically without
assigning the same prospective job twice. This is a next-dispatch forecast, not a
claim to predict all unknown future terrain or a full-project completion time.
Report active fuel, next-excursion demand, shortfall and required configured fuel
items. Distinguish observed stock, reserved/in-transit supply and estimates.

Station service raises its worker's target to the next mission requirement when
that exceeds the normal target, bounded by the reported native fuel limit. If a
mission exceeds that limit, show the exact limitation instead of looping refuel
jobs indefinitely. Preserve the existing finite station batch size, refill journals,
inventory lock, offline-owner exclusion and measured-fuel retry behavior. A worker
above the low threshold but below its next mission budget refuels proactively.
Existing production requests acquire missing station fuel; do not add a second
resource ledger or count forecast items as delivered fuel.

## Validation

Use red/green tests for every role, finite/unlimited fuel, unknown pose, overhead
travel, partial task progress and legacy telemetry. Queue tests cover a poor-fuel
worker preceding a ready one, a changed budget during a yielding coverage call,
and recovery ownership unaffected by new forecast decisions. Station tests cover
above-low proactive refill, measured repeated batches, fuel-limit errors, restarts,
offline owners and exact stock receipts. Actual-runtime and native acceptance
must show queued useful work triggers refueling before ordinary assignment and
then completes with conserved fuel-item accounting. Run one final branch review,
the consolidated regression pass, complete suites and release checks.

Ruling: reuse bounded mission excursions instead of introducing a speculative
whole-world route optimizer. This preserves existing mid-job refueling; forecasts
are explicitly scoped and may increase as new work or terrain becomes known.
