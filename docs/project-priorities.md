# Project priorities

Use `build priority <name> <0..100>` to set relative priority. Projects default to
50. Higher numbers receive the next eligible work, uncommitted material claim and
supply offer first. `build status <name>` and `build forecast <name>` show the saved
priority. Changes survive controller restarts.

Priority follows the project through production requests, material acquisition,
factory jobs, preparation and construction. Existing job IDs, assigned workers,
stock/capacity leases and physical journals retain their owners. Changing priority
does not interrupt a turtle or reclaim staged inventory. Returns, fuel recovery,
inventory recovery and active access restoration keep precedence.

Concurrent projects share the existing factory admission boundary. Mining/status
can advance for several requests, while one request admits new manufacturing work
per finite operation/batch boundary. Parallel furnaces, processors and private
Crafty workers still run within that operation. When a higher-priority request is
ready, already committed batches drain; empty losing preferences are retired and
replanned from observed stock. Missing unclaimed ingredients reopen acquisition
instead of leaving a factory job blocking its own miners.

Among eligible workers, dispatch prefers the smaller conservative mission fuel
budget, then a worker with fewer competing roles, then worker ID. Unknown geometry
sorts after known routes. Capability, fuel, health, chunk, protection and ownership
checks still decide whether work is feasible; an estimate is not a measured trip.

Paused or unavailable work does not receive new claims. Existing committed work
still obeys its physical coordination barriers. Strict priority can delay lower
projects while higher demand continues; there is no implicit priority aging.
