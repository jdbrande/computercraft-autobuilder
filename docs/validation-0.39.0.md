#0.39.0 shared traffic acceptance candidate

Final implementation32e3cfc. The complete Lua gate is running;23 Python tests,
focused shared-world/queue/dashboard regressions and native acceptance passed.
This candidate remains unaccepted until its complete gates and ordered integration.

## Automated evidence

The shared physical fixture covers a four-role intersection, opposing verification
workers in a roofed one-cell passage, and an offline destination owner while
independent work completes. Successful moves require the controller's matching
reservation and distinct actual worker cells. Mining/transport receipts and final
inventories are exact; terrain is shared, not separate per-worker copies. The
corridor case preserves walls and ownership through controller/worker restarts.

The trial exposed a diagnostic gap: repeated generic reservation waits hid a prior
specific physical detour obstruction. Generic, fixed-mining and exploration queues
now retain the last detailed route failure until actual work resumes, with failed-
checkpoint rollback and restart coverage. This is historical diagnostic evidence,
not extended reservation ownership. The single final review found that a current
traffic-wait row hid this history/remedy;32e3cfc displays both, regression-backed.
No new corridor scheduler or destructive automatic bypass was introduced.

## Native Minecraft —2026-10-04

PrismLauncher1.20.1 TESTINMG, Forge47.4.10, CC:Tweaked1.120.0 and Advanced
Peripherals0.7.48r. Final source32e3cfc used shipped5s heartbeat/15s registration/
30s timeout,8,000 finite starting fuel per turtle and15 explicitly loaded chunks.
Native runtime commands entered the ordinary queued CraftOS local-command API;
all travel, inspection, cargo transfer and rednet used real native APIs.

Controller268 coordinated verifier269, courier270, returning worker271 and
miner272 around(2910,302,10). All four owned useful work before release. Recorded
reservation denials crossed roles at the intersection. Courier270 shut down at a
known settled pose carrying one dirt, the controller restarted, and the registry
marked270 offline without releasing its contract. Independent verification finished
during the outage. Turning270 back on resumed the original haul: exactly one dirt
moved source→destination, and the miner delivered exactly one cobblestone. The
single stone target verified correct. All four workers settled home, idle and empty;
independent world reads confirmed the target, mined cell, inventories and computer
identities. This is recovery from settled shutdown, not an ambiguous power-loss move.

The first corridor fixture273/274 was rejected: sequential startup let a verifier
encounter an unregistered turtle before both assignments were ready, and the tiny
workload's one-builder target delayed the second owner. Its audit files remain;
those queues were shut down and are not acceptance evidence. The corrected separate
controller275/workers276–277 used separated initial positions and an explicit two-
builder minimum for this two-job contention test. Both owned opposing VERIFY jobs
in the roofed one-cell passage before release.

Both workers reported detailed stone-obstructed detours and retained their original
owners through controller restart. `fleet worker` named the job, position, cause and
passing-bay/alternate-route remedy. Independent commands confirmed all76 floor,
roof and sidewall blocks intact. Only after this negative acceptance did the
operator open two six-cell side bays. Normal resume completed both verifications
with one correct block each; both workers returned home empty. The bays are an
explicit operator correction, not autonomous excavation or construction credit.

Independent final reads confirmed both target blocks, worker identities and empty
cargo at home. All remaining fixture computers were independently confirmed off
and all15 force-load tickets removed. No backup was made and the player was not
moved. Rigs and target blocks remain. Ignored source/setup scripts, queued commands,
JSONL events, before/after snapshots and world receipts are in`dist/live-traffic/`.

The result proves bounded safe contention and actionable unresolved passage failure
in a staged loaded rig. It does not promise arbitrary narrow-corridor deadlock
resolution, destructive automatic passing bays or unrestricted terrain throughput.
Sustained16-worker load and final combined unassisted construction remain next.
