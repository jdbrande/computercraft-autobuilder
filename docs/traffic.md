# Shared fleet traffic

Mining, building, verification, hauling and home returns use the same controller
cell reservations. Every movement requires an adjacent grant; worker positions,
owned work areas and mutation guards keep other actors out. Losing contact does
not release a turtle's physical cell or task. An idle online worker occupying a
needed destination may receive an ordinary managed home return.

After a traffic denial, workers try existing bounded detours. Searches examine at
most256 nodes and remember at most16 obstacles for a candidate route. Workers do
not dig through another turtle or demolish a physical obstruction to make a detour.
An enclosed one-cell passage can legitimately remain blocked without a passing bay.

`dashboard` or `fleet worker <id>` identifies the task, worker, known position and
current reservation wait. If physical detour planning fails, the last detailed
route failure remains visible through generic pending reports, with corrective
guidance. This is a historical explanation, not a claim that an old blocker still
occupies a cell. Normal work, completion or a different failure clears it.

Inspect the corridor and implicated worker. Restore an offline owner's connection,
provide a passing bay or a clear alternate route, then use the existing task resume
command if needed. Preserve owned tasks and inventory journals. Reconnect and
normal acknowledgements reconcile ownership; expiry never means an abandoned
physical turtle disappeared.

Shared-world runtime tests cover four roles crossing one intersection, exact
courier/miner delivery, opposing roofed-corridor workers through restart, and an
offline destination owner while independent verification finishes. All simulated
moves check actual distinct worker positions and controller grants; all corridor
blocks remain intact. Native traffic acceptance and complete gates are pending.
