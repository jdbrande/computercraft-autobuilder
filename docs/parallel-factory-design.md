# Parallel factory and capacity ownership

Scope: requirements12–16 and the factory dependency of dynamic scaling (44).
Extend the current queues, ingredient ledger and Crafty engine. Preserve legacy
single-station work. No new dependencies or independent scheduler.

## Selected contract

Multiple configured Crafty stations execute finite batches concurrently. Each
station has a registered worker and three distinct wired inventories: a private
buffer, adjacent crafting input, and adjacent output. Controller and worker agree
on these names; worker advertises `isolatedCraftingV1`. Worker configuration retains
physical input/output sides. Inputs and completed output live in the private buffer
while the worker owns it. Workers never touch central storage in this mode.

The controller holds the existing inventory action lock for shared transfers.
It reserves ingredient counts, exclusive private inventories and central output
capacity before staging. Staging uses the existing transfer journal, observing the
private destination. The worker receives its saved assignment only after the exact
input batch is staged. Concurrent workers mutate distinct inventories. Legacy
shared-inventory jobs retain their barrier until migrated in later pipeline work.

A durable capacity ledger reserves concrete destination slots and amounts, using
native inventory size, slot limits and measured item stack limits. Unknown item
limits are conservatively one per slot, never guessed as64. Existing item details
allow larger reservations once observed. Exclusive claims additionally prevent any
other owner from using private station inventories. Claims survive offline workers,
partial movement and restart; changed duplicate contracts and failed saves fail
closed. Output transfers use reserved slots and recheck actual capacity.

Each station receives at most one outstanding batch. Default maximum is two recipe
batches; configurable bounded larger batches remain subject to measured capacity.
The planner divides the remaining operation among eligible idle stations, retaining
exact aggregate batches and output rounding. Saved batches never move to another
worker after assignment. A disconnected station does not duplicate its batch;
other ready stations can finish their independent shares.

Worker completion is persisted and acknowledged, then the controller collects the
private output. The job remains owned/collecting until all expected output reaches
central storage, all three station inventories are empty, and count/capacity claims
release. Private worker receipts never credit shared stock. Delayed completion or
progress cannot reopen a collecting/completed job. Controller transfer journals and
worker craft journals use separate state and receipt sequences.

## Alternatives rejected

Removing the global factory barrier alone is unsafe: existing journals observe
shared inventories and yielding stock snapshots race worker effects. A distributed
per-action lock protocol adds network handshakes and ambiguous lock recovery to
every craft step. Private finite staging reuses existing journals and permits native
parallel crafting with a smaller recovery surface.

## Acceptance and limits

Tests cover capacity exhaustion, stack limits, conflicting claims, atomic saves,
partial transfers/reboots, duplicate receipts, two simultaneous Crafty workers,
shared-material requests, disconnected stations, empty inputs and full outputs.
Native acceptance uses two real Crafty turtles concurrently, exact input/output
accounting and reboot recovery. Document setup and measured results; review,
regressions, complete release checks and integrate before continuing.

This milestone does not declare full continuous-pipeline acceptance: legacy miners,
shared supply and furnaces still use the existing physical barrier. General courier
capacity/routing, machine adapters and cross-role pipeline scheduling follow under
the full requirements. Capacity ownership is reusable for those consumers.
