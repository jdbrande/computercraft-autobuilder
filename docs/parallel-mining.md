# Parallel mining areas

For guided setup, use `setup miner stone,coal`, `setup miner sand`, or
`setup miner clay` on different turtles. Follow the [material-team guide](material-team.md).
Optional `mining.resources={'minecraft:cobblestone','minecraft:coal'}` restricts a
worker to those requested drops. Empty or omitted resources means unrestricted.
The controller matches each missing resource to an eligible worker and preserves
that resource restriction with its durable assignment. A changed worker profile
does not silently redirect an already owned job.

Multiple miners can work concurrently when each worker advertises a configured
mining box that does not overlap any active mine. Configure separate
`mining.bounds = { min={x=...,y=...,z=...}, max={x=...,y=...,z=...} }` boxes and valid
entry/depot coordinates in each worker's `settings.lua`, then enable mining. Worker
registration and heartbeat telemetry include a defensive copy of these bounds as
`miningArea`. Disabled mining does not advertise an area.

The scheduler assigns separate queued material jobs to idle capable workers in
worker-ID order, preserving job priority and dependency ordering. Two boxes overlap
when they share any block coordinate; touching inclusive boundaries therefore
conflict. Adjacent boxes with no common cells are permitted. For example, one box
ending at x=8 and another starting at x=9 can coexist if their other coordinates
would overlap. A box starting at x=8 cannot run beside that first box.

The controller persists `job.workerId` and `job.miningArea` together before dispatch.
That snapshot remains authoritative across worker disconnection, changed telemetry,
and controller restart. An offline worker's job and area are retained; another
worker is never assigned that job or allowed to claim its area automatically.
A worker cannot own two active physical mining jobs, even if its last heartbeat
still says idle. Running or blocked jobs retain ownership without being repeatedly
returned by the assignment scheduler. Newly eligible jobs can therefore reach other
miners. Pending assignments are retransmitted fairly until progress arrives.

Workers using older telemetry without `miningArea` still work, but their active
physical mine conflicts with every other mine. Historic `miningWorkerId` checkpoint
pins no longer restrict workers with explicit bounds: ownership is tracked per job.
A restored older job without a saved box remains exclusive until its physical work
finishes. Invalid or reversed advertised boxes are rejected, and each axis may span
at most 256 blocks, matching worker configuration validation.

When recovery finds a queued controller job already running on a registered worker,
`recoverOwner` requires that worker's matching task ID, original assigned quantity,
and mining capability. It applies the same owner and area conflict checks before
persisting the recovered ownership. A conflicting recovery is blocked for operator
inspection rather than taking over another miner's area.

Area ownership covers excavation bounds. It does not itself reserve travel routes,
shared depot cells, or inventory transfers. Runtime movement reservations must remain
active for those shared spaces. Operators should configure usable access routes and
avoid changing a worker's bounds while it owns a job; the runtime must reject a
saved assignment whose bounds no longer match that worker's configuration.

The scheduler continues to use live storage at assignment, protects job dependencies,
and handles delivered stock, supplements and duplicate completion reports as before.
It schedules separate requested material jobs; it does not split one material job
among several miners. The automated tests exercise simultaneous disjoint ownership,
overlap rejection, offline leases, assignment retransmission, checkpoint restoration,
and recovery conflicts. They do not constitute a live Minecraft multi-turtle test.
