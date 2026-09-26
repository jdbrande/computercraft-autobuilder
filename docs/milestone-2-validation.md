# Milestone 2 validation record

Implemented only mining/resource logistics after the user's instruction to continue.
Milestone 3 and later remain out of scope. No live Minecraft instance is attached.

## Architecture decisions

- Reuse the existing controller and worker, adding separate jobs, mining service,
  scanner, materials, pathfinding, cargo and storage modules.
- `mine item N` targets depot stock N, subtracting stock at submission and assignment.
- Keep one persistent physical mining worker for this milestone. Offline ownership
  does not expire into duplicate assignments; parallel miners remain Milestone 8.
- Use a pickaxe/scanner swap in slot 16, preserving the modem. Verify server cooldown
  through AP's `getOperationCooldown('scanBlocks')`, with a bounded wait. Only free
  scans are allowed so scanner cost cannot consume movement reserves.
- Use a separate action coroutine, with GPS requesting a stable hardware boundary.
  Keep heartbeats active during scanner, turtle and refueling waits.
- Preserve move/drop intent and actual inventory accounting across reboot. Stop for
  uncertain pose or protected obstacles. Supply shortfalls and full chests preserve
  cargo/progress, and support explicit resume after remediation.
- If storage changes during work, schedule uniquely identified supplemental jobs;
  cap automatic supplements at three and expose an explicit replan command.
- Preserve default telemetry-only behavior unless mining is enabled and configured.

## Independent review

A separate reviewer examined the implementation and ran the then-current 53-test suite.
Each actionable finding was reproduced by a failing regression test and corrected:

1. Wrong scanner side could detach the modem: reject modem-side swaps before equip.
2. Partial fuel stack could prevent using stocked fuel chest: bounded refill/consume
   loop checks actual fuel progress and accesses the chest when the stack empties.
3. Stock consumed during an assigned job could leave it permanently blocked: persist
   a supplemental job with a new ID and acknowledge the completed physical delivery.
4. Failed tool restoration could fall through into strip mining: distinguish fatal
   restoration faults and block mining until tool recovery succeeds.

A further failing integration test exposed controller backup rollback losing assignment
ownership. The controller now reconciles a known queued job against the uniquely
matching registered worker task and its persisted assigned quantity before resuming.

Other reproductions fixed during implementation include: delayed GPS pose recovery,
GPS calls racing motion, idle action loops invalidating fixes, scanner cooldown waits,
fallback surveying only endpoints, travel fuel shortages, obsolete queued stock,
unexpected route obstacles, and manual allowlists being broadened by defaults.

## Test scope

The offline suite uses Lua 5.2, with filesystem and serialization fixtures, a simulated
block world, physical turtle pose/inventory/fuel, scanner upgrades and wired depot
stock. Actual controller, worker, network, storage and miner modules execute in the
end-to-end tests. It exercises mid-job reboot of both endpoints, duplicate assignments,
lost completion ACKs, deposit/movement crash journals, bounded A*, depot-full recovery,
inventory resupply trips, consumed-stock supplementation, hardware faults, protected
blocks, configuration validation and all Milestone 1 regressions.

Final verification: `.venv/bin/python tests/run.py` passed 68 tests; Lua 5.2 syntax
checks passed for all 36 Lua files; all four documented configuration examples
validated through the real configuration loader. These tests do not
model full Minecraft physics, modpack configuration or actual chunk/network loading.
Run the live acceptance checklist in milestone-2.md before relying on real excavation.

## Operational limits

Requires a correctly configured mine volume, known heading, player-cleared depot
corridor, a real output inventory and sufficient fuel. Fallback survey covers configured
strips at entry depth; it reports exhaustion instead of searching the entire world.
Unresolvable interrupted turns/backup poses require operator confirmation. Neither
checkpoint snapshots nor rednet IDs are cryptographic protection against hostile
players, externally edited inventory, or simultaneous historical disk/clock rollback.
