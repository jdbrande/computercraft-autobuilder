# 0.20.0 interrupted movement recovery acceptance

Scope: evidence-bounded translation reconciliation, automatic GPS heading probes,
atomic recovery traffic ownership and resumption of the original task. Broader route
recovery, rescue, registration and project settlement remain separate required work.

## Automated evidence

Final gate:589 Lua/18 Python tests passed. Release0.20.0 generation/check and
`git diff --check` passed. One whole-branch review and its consolidated fix pass
are complete; the four findings and native fallback retest are recorded below.

Regressions first failed, then passed for unexpected GPS relocation, malformed
translation envelopes, preservation after failed saves, uncertain turns, saved
coverage after policy opt-out and normal execution with an unresolved heading.
A separate regression reproduced five physical moves by disabled worker automation;
the runtime now retains its saved task without executing it.

Actual runtime tests deliver nine items exactly once after an interrupted upward
move, and after a turn followed by another reboot during the heading probe. Both
controller and worker restart; lost grant and settlement acknowledgement recover.
Pause and unrelated blocked-task state remain intact. Probe tests cover interrupted
backtrack, GPS outage/mismatch, protected/unloaded/occupied cells, competing task
regions, fuel/obstacle refusal, changed messages and checkpoint rollback. Controller
claims all candidate cells in one checkpoint and releases them only after the worker
returns to the saved origin. A malformed refusal-reason test protects status payloads.

## Native Minecraft — 2026-10-03

Local PrismLauncher1.20.1, TESTINMG, Forge47.4.10, CC:Tweaked1.120.0 and Advanced
Peripherals0.7.48r. Controller160 and courier161 used normal fleet modules and real
wired inventory, turtle, rednet and GPS APIs. Computers162–165 ran CraftOS's native
GPS host program at `(508,292,-8)`, `(540,292,-8)`, `(508,292,12)` and `(508,312,-8)`.
The fixture occupied approximately `(508..540,292..313,-8..12)`. Existing computers
0–9 were untouched. No backup was created.

The source contained64 stone and7 dirt; destination and private buffers were empty.
Courier161 began with2000 finite fuel. A nine-stone destination target automatically
created one managed haul. Six operator force-loaded chunks supplied the declared
mission envelope. This trial does not repeat0.18's native chunky loading evidence.

The harness wrapped native movement methods solely to reboot **after the real API
returned success but before navigation could confirm the effect**. Four one-shot
interruptions ran during the same original task:

1. Upward movement with nine stone held. All four GPS hosts remained off for at least
   ten seconds after interruption; the worker retained uncertain pose and ownership.
   Starting the real hosts allowed recovery without a pose command or checkpoint edit.
2. A turn with cargo held, leaving heading ambiguous.
3. The native forward heading probe, before its GPS receipt.
4. The native backtrack, before navigation confirmed return to the probe origin.

The controller also rebooted after the physical heading probe. Recovery retained the
same job and sequence, returned to `(516,303,0)`, settled its cell claims and completed
the original delivery automatically. The observed trial completed in39.30 seconds.
No operator supplied more items/fuel, moved the turtle or corrected its checkpoint.

Independent command-computer world reads confirmed source55 stone plus7 dirt,
destination9 stone, both private buffers empty, and the actual turtle at
`(532,301,0)` with empty inventory and1978 fuel. Final controller state showed one
completed haul/job, settled pose claim, and released count/capacity/chunk leases.
The worker was idle with east heading and no current task or recovery record.

All six computers were shut down; the six fixture force-load tickets and observer
ticket were removed. The rig and stocks remain inspectable. Local ignored evidence
under `dist/live-pose/` includes setup/response, continuous states, each post-effect
cut record, unresolved GPS-outage state, final snapshots, independent world reads,
result and cleanup. The audit observes normal runtime state and routes operator input
through the normal event boundary; it is not terminal-input reliability acceptance.

## Final review and fallback retest

Four Important findings were reproduced and fixed in one review pass:

- Controller fallback could forget an issued probe claim. Validated worker recovery
  telemetry restores claims before backup scheduling or movement is allowed. A
  durable worker settlement receipt reconciles a controller snapshot from before the
  acknowledgement. Fresh controller-generation acknowledgements revoke unexecuted
  old grants; the barrier waits for their echoed generation before reopening work.
  Delayed grants from the old controller cannot cross that boundary.
- Worker fallback deliberately clears heading. A return-stage probe now restores its
  measured heading while still validating any pending backtrack movement journal.
- Mining-only workers accept their owned recovery controls even when generic
  automation is disabled; unrelated generic effects remain disabled.
- Optional depots no longer cause a nil-index exception during probe fuel checks.
  The forward/backtrack reserve still applies when no home is configured.

Additional regressions cover malformed/cyclic extra telemetry, lost settlement
acknowledgement followed by GPS loss, acknowledged-settlement fallback and delayed
old-controller grants. No physical journal is discarded to unblock a worker.

A second native run raised the destination target from9 to18 and automatically
scheduled one more nine-stone haul using the remaining source stock. Test wrappers
corrupted only the primary controller checkpoint immediately after actually sending
a recovery grant, and the primary worker checkpoint before the native backtrack.
Both loaded their existing normal fallback checkpoints. The captured controller
fallback explicitly contained **no probe claim**; the worker fallback contained the
return stage at the adjacent cell with its previously measured north heading, which
runtime startup deliberately invalidates before recovery.

The original second job recovered and completed in33.80 seconds. Independent world
reads confirmed source46 stone plus7 dirt, destination18 stone, empty private buffers
and turtle, and1936 fuel. All jobs/hauls completed and claims settled/released. The
same six computers and all fixture/observer force-load tickets were shut down/removed
again. Evidence is retained in `dist/live-pose/fallback-*` and its two audit records.
The final controller-generation fencing refinement follows this native retest and is
covered by an actual runtime delayed-packet/fallback regression.

## Limits

GPS-backed translation and bounded heading recovery were exercised in loaded open
lanes. This does not establish arbitrary terrain routing, obstruction removal, lost
hardware/inventory rescue, fleet deadlock resolution, idle registration calibration,
GPS-host provisioning or safe final home/unload settlement. These remain required in
the fleet ledger. A nonadjacent GPS fix or unreachable probe stays visibly owned.
The final refusal-display change follows the native trial and has protocol regression
coverage; it does not change the physical recovery sequence.
