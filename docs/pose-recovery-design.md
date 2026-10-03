# Automatic recovery of interrupted turtle movement

## Required outcome

Requirements24–26 and35–38 require a worker to retain its task and physical journals
through a reboot and resume when physical evidence resolves its pose. Native0.19
exposed an actual interrupted upward move. This milestone resolves translations and
ambiguous turns using real GPS; it does not declare broader rescue, route recovery,
final settlement or registration complete. They remain in the fleet ledger.

## Evidence before effects

A pending translation contains its starting and intended ending coordinates. A GPS
fix at either coordinate resolves whether the effect happened; any other position
retains the journal and reports an actionable mismatch. An explicit operator pose
confirmation remains an intentional override. GPS does not infer heading from a
turn: pending turns resolve coordinates but invalidate heading. Failed checkpoint
writes retain uncertain state. Normal execution cannot act with unknown heading.

Runtime records a pose-related blocked task separately from unrelated engine errors.
After reliable coordinates and heading return, restore only that task's execution
phase through its existing resume handler. Never discard excavation, cargo, supply or
placement intents. Paused tasks stay paused; disabled services do not start effects.
GPS queries retain the existing motion-version and busy exclusion around yielding APIs.

## Heading recovery

For an active owned task with a GPS fix but unknown heading, save a recovery record
with task ID, unique sequence and origin. Request one atomic reservation covering
origin and its four horizontal neighbors through the existing controller workflow
queue, shared by mining and generic workers. All possible probe destinations must
satisfy loaded coverage, infrastructure protection and traffic ownership. A denial
retains the task and retries at the heartbeat interval. Claims survive disconnects
and reboots; duplicate requests must exactly match the saved sequence and origin.

After a durable grant, inspect forward without digging. Require finite movement and
return fuel, an unpaused task and enabled service. Persist probe intent before one
native forward move. Locate GPS again; reuse core.gps.heading(origin,fix) to infer
heading only from exactly one horizontal block. Persist the recovered heading and return stage, then use journaled navigation to
backtrack to the origin under the same claim. Confirm origin with GPS, report the
settled position to release unused cells, then resume the original engine. Returning
to origin preserves miner trail and pending-move journals. A reboot during backtrack
reconciles the ordinary translation intent before any further move.

A reboot after the physical step but before its receipt uses the saved origin and
fresh GPS; it must not repeat the probe. If fresh GPS is still at the origin, no
translation occurred and a later guarded retry is allowed. Any nonadjacent result
stays unresolved. No GPS result means no additional blind movement. A blocked front
reports the obstruction without digging or dropping cargo. This conservative probe
requires one accessible forward cell; general obstacle rerouting remains required
subsequent work. Idle first-install heading calibration belongs to registration work.

## Integration and bounds

Use navigation, GPS, workflows, chunks and executor/miner resume contracts already
present. Add only the bounded recovery driver and protocol fields needed for atomic
claims and receipts. Existing physical task ownership never expires due to recovery.
Saved loaded grants remain binding even if current chunk enforcement is disabled.
The dedicated recovery driver runs before normal unknown-pose execution rejection,
with its own strict gates; normal task effects retain their ordinary coverage guard.

## Acceptance

Reproduce translation from/to/mismatch, failed checkpoints, uncertain turns, unrelated
blocked tasks, pauses and disabled services. Test atomic four-neighbor ownership,
changed duplicates, lost grants/receipts, controller/worker reboots, protected or
unloaded neighbors, foreign workers, no fuel, obstruction and GPS outage. Use actual
runtime engines for interrupted movement and cargo conservation. Native acceptance
uses real wireless GPS hosts and one-shot reboot injection after a real turtle move
or turn but before software confirmation, independently inspecting the final world.
No simulated GPS positions or direct checkpoint repairs count as live recovery.

Complete one whole-branch review/fix pass after implementation and useful native
acceptance, integrate, then continue every remaining fleet requirement.
