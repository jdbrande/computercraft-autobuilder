# 0.15.0 fuel management acceptance

Scope: configurable fuel, dedicated station distribution, automatic depot refuel,
stranded-worker rescue and durable delivery/consumption/release. This is one
integrated milestone in the larger [fleet requirements](fleet-requirements.md).

## Automated evidence

Pre-review gate:466 Lua tests and all16 Python tests passed. Release generation,
`python3 tools/release.py --check` and `git diff --check` passed. Tests exercise real runtime/controller/worker modules with simulated
hardware, including finite fuel, partial deliveries, unrelated inventory changes,
missing/full stations, failed checkpoints, offline ownership, duplicate receipts,
reboot after a transfer or burn, returned lava buckets, wrong recipient identity,
protected/blocked routes and original-task recovery.

The full rescue runtime test drops a consumption receipt and restarts controller
and recipient. Only newly delivered fuel is consumed; pre-existing coal remains.
The courier returns, the original task completes and the rescue settles once.

## Native Minecraft acceptance — 2026-10-03

World `TESTINMG`, PrismLauncher Minecraft1.20.1, Forge47.4.10, CC:Tweaked1.120.0
and Advanced Peripherals0.7.48r. Test computers110–115 and a new rig at
approximately `(176..194,300,0..4)` use native rednet, turtle and peripheral APIs.
The operator supplied20 raw coal to a wired source chest and force-loaded the
mission envelope. No world backup was made, as authorized. The player was not
moved during this trial; original computers0–9 were not changed.

Controller110 automatically filled dedicated overhead fuel chests. Worker113
started with zero fuel and refueled to160. Worker111 also started at zero, with an
operator-seeded RETURN_HOME task and a home four blocks away. Courier112 started
with500 finite fuel, collected two coal from its station, identified111 through
its adjacent native computer peripheral, delivered fuel and returned to its depot.
The recipient consumed the measured delivery, kept its original task and returned
home with152 fuel. Controller and recipient were rebooted while rescue ownership
was active. The courier returned with462 fuel after the fixes below.

### Bugs found and corrected

- Returning down the ordinary overhead route hit the station's fuel chest. Fuel
  routes now descend beside the stand and enter horizontally. The route regression
  failed before the fix. The first courier job was resumed after deployment.
- The controller received raw release packets while waiting for peripheral calls,
  but the main coroutine's event filter discarded them. An independent harness
  listener observed the packets; the normal receive handler did not. A regression
  reproduced the loss. A bounded network collector now retains packets for the
  main coroutine, which remains the only control-state writer. Deployment allowed
  the saved rescue to release without inventing a completion receipt.
- The runtime simulation found that a remotely refueled worker retained its old
  fuel-detour state and demanded another top-up after reaching home. Successful
  rescue now clears that detour before resuming the original task.
- A stale low-fuel heartbeat could create another rescue after release. The
  controller now requires a newer recipient heartbeat before scheduling again.

### Fresh acceptance after fixes

New workers114 and115 started with zero fuel. Worker115 automatically refueled at
its new station to160. Worker114 kept an operator-seeded RETURN_HOME task, received
two coal through automatically assigned courier112, then completed its original
return with152 fuel. The courier returned to its depot with420 fuel remaining.
No manual rescue assignment, fuel transfer or task resume occurred in this retest.

Both rescue jobs reached completed/released. All13 test jobs completed, all station
inventory claims released, no production requests remained, and all workers were
idle. The independent command computer read actual world fuel values152,420,160
for114,112,115. Source storage held6 coal and the three station chests each held2:
20 initial coal =8 consumed by the four recipients +12 remaining. No additional
fuel was supplied during either run.

Snapshots, raw network diagnostics, setup scripts, inventory checks and audit
streams are under ignored `dist/live-fuel/`. All six test computers were shut
down and all27 test force-load tickets removed after verification. The rig remains
for inspection. The harness submits operator test work
at runtime boundaries and observes state; it does not substitute simulated turtle
or inventory APIs for live worker actions.

## Limits and remaining requirements

This trial proves station distribution and identity-checked rescue in a clear,
loaded envelope. It does not prove arbitrary terrain routing, chunk loading,
bootstrap from a fleet with no fuel, fleet-wide predictive fueling for every job,
automatic recovery of unreachable inventories or large-scale traffic management.
Station capacity and frozen recipients remain exclusive until durable release.
Ordinary refueling retains returned containers until a verified depot accepts them;
rescue-returned containers remain in the recipient's inventory.

Missing station stock enters ordinary resource planning; this trial deliberately
supplied raw fuel to isolate distribution and recovery. Dynamic fleet scaling,
terrain leveling and automatic site preparation in sections44–45 remain required
subsequent capabilities. See [fleet progress](fleet-progress.md) for all open work.
