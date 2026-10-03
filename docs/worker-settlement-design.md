# Worker home unloading and project settlement

Requirements25/38/43–45 need safe inventory release before project completion or
role reassignment. Existing RETURN_HOME travels but leaves cargo held; VERIFY marks
projects built before acknowledgements and return. Reuse native registered logistics
buffers, inventory/capacity ledgers, navigation and existing physical journals.

## Home return contract

An explicit `worker return ID` or an automatic project settlement request waits for
that worker's current task to settle. It then uses fresh idle telemetry containing
bounded nonreserved cargo counts and observed stack limits. Reserved fuel/tool slots
are excluded with the existing resupply.reserved rule. NBT cargo remains visibly
blocked for supported identity handling; never drop or silently discard it.

Use the registered logistics private buffer whose stand equals the worker's depot;
its node identifies central wired storage. For cargo, reserve exclusive buffer room
and concrete central output slots together with an output-only count lease and the
immutable RETURN_HOME contract. No central ingredients are claimed: these items are
already in that turtle. Empty-cargo return needs only a known depot and loaded route.
Read-only observations and a final eligibility check run under inventoryAction.
Until this checkpoint a logical return request does not pin or move a worker.

The worker verifies its assigned cargo against actual nonreserved inventory, follows
journaled overhead travel, checks the native container and drops only the assigned
items. Persist each drop intent and complete inventory snapshot before the native
call; use existing measured delta reconciliation after restart. Never infer a drop
from requested quantities. A missing/full container or ambiguous slot mutation
retains ownership and its exact error. Reserved slots never change during unloading.

Worker completion reports monotone exact per-item deposited counters. The controller
keeps the job collecting, its worker/buffer/loaded claims held, and waits to acknowledge
until journaled transfers place every item in the concrete central allocations.
Output count receipts reflect central collection, not a worker's private deposit.
Reboots, offline owners, lost/changed receipts and changed node configuration retain
contracts. Setup errors name the missing home/buffer/capability; no world drops.

## Project completion

After final verification succeeds, enter settling. Derive all project actors and
linked production/supply/acquisition work across phase generations, using existing
retirement linkage and fresh worker acknowledgement checks. Wait for physical jobs,
stock/capacity/supply/loaded claims and transfer journals. Request safe returns for
idle actors; prove home position and empty nonreserved cargo after their last task.
A compatible durable reassignment may release an already empty actor, preserving
ownership by its new task. Do not force home trips between ordinary build batches.
Only then checkpoint built/verified. Failures stay visible with exact blocker.

Bounded return jobs initially require room for the worker's finite cargo manifest;
other independent workers may settle while a destination is full. Larger continuous
flow and inventory rescue remain required separate work, not completion exceptions.
An operator's newly registered idle turtle is not automatically emptied: returns need
an explicit command or recorded project participation.

## Acceptance

Simulate mixed cargo, protected slots, actual native capacity, missing/offline/full
containers, changed contracts, partial drops/collection, duplicate/lost receipts,
controller/worker interruption after effects, failed saves and concurrent ownership.
Project tests prove verified blocks alone cannot produce built, while settlement and
safe compatible reassignment do. Native acceptance returns finite cargo from a remote
worker and checks central/private/turtle world inventories, position and fuel, with
restart injection. Run one final branch review/fix pass, integrate, then proceed to
mandatory full site preparation, dynamic scaling and all remaining fleet requirements.
