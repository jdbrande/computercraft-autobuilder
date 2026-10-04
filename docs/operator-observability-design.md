# Operator observability

Milestone0.38 closes the monitor, command and significant-event gaps in
requirements32–34, and adds durable traffic diagnostics needed for later contention
acceptance. It builds on existing state and coordination; no route scheduler or
new remote-control protocol is introduced.

1. Record changed traffic waits on owned jobs with target, reason, blocker and
   first-seen time. Repeated retries keep their identity; successful grants clear
   matching waits. Preserve offline ownership and show an actionable remedy.
2. Extend the existing event collector to retain operator input while native
   peripheral calls yield. Main remains the sole control-state mutator. Bound the
   queue; overflow discards an entire keyboard command, never executes a prefix.
   Add a correlated local CraftOS command/result event using the same dispatcher.
3. Add bounded structured JSONL events after successful ownership/receipt/phase
   checkpoints. Keep rotation and ordinary messages, avoid heartbeat/retry floods,
   and never announce draft ledger claims before their enclosing checkpoint.
4. Add a small read-only status projection for projects/materials, role allocation,
   workers/fuel/cargo/heartbeat age and errors. Cached unknown stock remains unknown.
   Rendering must not analyze schematics or call physical inventory APIs.
5. Render that projection on an optional configured native monitor and expose
   coherent command aliases/details. Resize/detach/reconnect must not stop work.

Tests exercise yielded peripheral calls with keyboard/paste/script traffic,
exact-once command execution, overflow, read-only monitor paging/detachment,
parseable rotated events, failed checkpoint suppression, changed traffic waits,
and restart. Native acceptance uses a real monitor, actual terminal input during
inventory traffic, a local script command, detach/reconnect and independent final
world/state checks. Record duration, command latency and backlog/drop counts.

One final whole-branch review and one consolidated fixes pass precede integration.
Subsequent work remains mixed-role traffic acceptance, sustained fleet load at
shipped telemetry settings, and the final unassisted combined fleet build.
