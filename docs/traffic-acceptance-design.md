# Shared traffic acceptance

Milestone0.39 addresses fleet requirements29 and39 using the existing durable
cell reservations, owned regions, observed obstacles, bounded detours and0.38
traffic diagnostics. Corridor/intersection abstractions in the requirements are
examples, not additional mandatory schedulers. Add an algorithm only if a physical
reproduction demonstrates that the existing mechanism cannot meet the contract.

Use a shared physical world for all actors. Every successful move must leave
workers in distinct cells; inspect every dig against the shared block map and
protected infrastructure. Separate per-worker terrain cannot prove collision
safety. Retain finite fuel, native executor messages and controller checkpoints.

1. Exercise an intersection with construction/verification, courier, home return
   and mining movement. Measure a cross-role denial at a shared XYZ cell and
   eventual completion with exact cargo, unchanged infrastructure and no collision.
2. Exercise opposing workers in a roofed one-cell passage without a passing bay.
   Accept either safe bounded completion or a durable visible blockage naming the
   worker, target, cause and remedy. Restart the controller while ownership is
   retained; do not manufacture progress by clearing reservations or moving actors.
3. Exercise an occupied destination. Idle occupants may receive the existing
   managed return. Offline or busy owners keep their claims, independent work
   progresses, and reconnect resumes the original contract.
4. Run a small native mixed-role intersection/corridor trial with shipped5s/15s/30s
   telemetry settings, a controller restart and an offline owner. Independently
   inspect final blocks/inventories; archive diagnostics and clean up test tickets.

Run focused meaningful regressions, one final whole-branch review, one consolidated
fixes pass and complete test/release gates. Integrate after dependencies pass.
The next work is sustained16-worker native acceptance for at least30minutes with
real unfinished work, then the final combined unassisted schematic fleet build.
Neither many registered idle workers nor configured128-worker limits prove scale.
