# 0.35.0 reachable inventory recovery validation

Candidate implementation `2e70326` passed focused tests and native acceptance.
The inherited 0.33 supply-ascent correction is included for final gates. The full
Lua gate remains pending; this is not a release acceptance claim.

## Automated evidence

Sixteen focused recovery tests cover frozen donor ownership, wrong computer ID,
exact item/NBT snapshots, partial receipts, interrupted donor/deposit/collection
transfers, unrelated inventory changes, insufficient fuel, failed checkpoints,
private destination capacity and protocol bounds. A real controller/donor/courier
runtime simulation reboots all three after a physical donor drop, then reconciles
both stacks, returns plain stock centrally and preserves tagged cargo and the
courier's original fuel stack. Runtime, automation, capacity, managed logistics,
node configuration and mission fuel regressions passed. All 20 Python tests and
release/diff checks passed before the inherited ascent correction.

The successful single final review found three integration stalls and one diagnostic
gap. The consolidated corrections add normal executor reconciliation for interrupted
courier deposits, a controlled station-refuel handoff for unassigned recovery trips,
and yielding when collection is waiting without a transfer journal. Recovery status
now includes the courier task and its error/admission failure. Tests reproduced the
three stalls before the fixes. An additional regression preserves the exclusive
courier reservation during the settled gap between trips. Donor ownership and
private buffer capacity remain held throughout refueling. No second review was run.

## Native Minecraft acceptance — 2026-10-03–04

PrismLauncher 1.20.1 `TESTINMG`, Forge 47.4.10, CC:Tweaked 1.120.0 and Advanced
Peripherals 0.7.48r. Controller 251, donor 252 and courier 253 use a separate rig
around `(2274..2296,300,0..4)`, with four operator force-loaded chunks. Both turtles
start with 2,000 finite fuel. No backup was created.

The ordinary command `transport minecraft:stone 5 pickup blocked` assigned donor
252, which physically picked up five stone from a chest and approached a destination
blocked by bedrock. It stopped above the obstruction with a confirmed pose, five
held stone and its original damaged diamond pickaxe in reserved slot 16. No donor
checkpoint or assignment was synthesized by the harness.

`worker recover 252` quarantined that blocked owner. Courier 253 was then available
with a registered empty private buffer under its depot and three coal already in
its reserved fuel slot. The controller created capacity-owned recovery jobs. The
courier approached above the donor, and both turtles checked the actual adjacent
computer ID before the donor selected and transferred its stack.

During the first receiving phase, the harness paused the courier job, waited for
its settled pose, rebooted all three computers and resumed that same custody job.
The two original stacks were collected through two measured jobs. The controller
moved the five plain stone from the private buffer into central storage and retained
the exact tagged pickaxe in the buffer. All recovery jobs and both capacity claims
settled. The original transport remains blocked and owned by quarantined donor 252;
cargo recovery deliberately does not repair or release its physical task.

Independent observer 90 block data confirmed:

- Central stock contains exactly five stone; the original pickup chest is empty.
- The private buffer contains one diamond pickaxe with `Damage:3`, unchanged.
- Courier 253 is home idle, holds only its original three coal, and has 1,928 fuel.
- Donor 252 remains at `(2296,301,0)`, empty and quarantined, with 1,981 fuel.
- The original bedrock obstruction remains intact; no recovery path was excavated.

The three computers were shut down and the four temporary chunk tickets removed.
The rig remains for inspection. Evidence is under ignored
`dist/live-inventory-recovery/runtime/`, including setup, original blocked task,
settled restart, completion, independent block data and cleanup receipts. Earlier
adjacent-turtle probes under the parent folder established native NBT-preserving
`dropUp` behavior. Native acceptance uses real turtle/peripheral/rednet APIs and
operator commands at the controller event boundary. It does not establish recovery
from an ambiguous physical move, powered-off donors, unreachable routes, arbitrary
terrain, automatic chunk loading or automatic repair of quarantined assignments.
