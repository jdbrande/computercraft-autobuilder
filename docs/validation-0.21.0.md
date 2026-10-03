# 0.21.0 capacity-aware crafting acceptance

Scope: automatic finite private-batch sizing, atomic count/capacity grants, safe
logical preferences and legacy unstarted-claim migration. Continuous cross-role
production, dynamic scaling and site preparation remain required subsequent work.

## Automated evidence

Pre-review gate:595 Lua tests and18 Python tests passed. Release0.21 generation/check
and whitespace validation passed. One final whole-branch review/fix pass is pending.

The high-yield pane regression reproduced the original capacity stall, then produced
64 panes from24 glass using the actual controller and two worker runtimes. Coverage
checks reject duplicate recipe execution and all claims/private inventories drain.
Other regressions cover native slot limits, cached read-only observations, capacity
changes before a real grant, unclaimed-worker pinning, an unusable station alongside
a feasible station, legacy stock-only claims across reboot, atomic-save rollback and
capacity errors in request status. Existing interrupted staging/crafting/collection,
partial transfers, lost acknowledgements and short-stock contention still pass.

Only granted intervals count as owned production work. A logical preference can be
replaced or retired without consuming ingredients or blocking another worker. Count
and capacity leases plus final quantities/journals are checkpointed together before
staging. Already owned batches retain their immutable quantities and journals.

## Native Minecraft — 2026-10-03

Local PrismLauncher1.20.1, TESTINMG, Forge47.4.10, CC:Tweaked1.120.0 and Advanced
Peripherals0.7.48r. Reused isolated controller120 and Crafty turtles121/122 around
`(224..236,299..302,0..2)`. Their old fixture stocks/checkpoints were reset; existing
computers0–9 were untouched. Both turtles started empty with2000 finite fuel, private
buffer/input/output chests and real wired/wireless modems. No world backup was made.
Two operator force-loaded chunks matched the explicit loaded-area configuration.

Trial1 supplied24 glass and no panes to shared storage, then requested64 panes.
The default maximum was two recipe executions, but32 unknown-stack outputs could
not fit a27-slot private chest. The controller automatically granted one execution
first (16 panes), then two and one executions after observing the real stack limit.
Both workers contributed; maximum observed concurrency was1 because the initial
central capacity was conservative. Completion took70.80 seconds. Independent world
reads confirmed64 panes, no glass, all six private chests and both turtles empty,
and2000 fuel each. No operator changed batch sizes or supplied finished output.

Trial2 added24 more glass and raised desired pane stock to128. Both workers received
two-execution batches concurrently. The controller and turtle121 rebooted during
concurrent crafting; the original jobs resumed without operator task correction.
The monitor observed20.44 seconds from attachment through completion; this is not
total request latency. Its initial completion check was corrected to wait for the
new128-pane request instead of accepting the prior completed request's snapshot.

Independent final world reads confirmed128 panes total, no glass, six empty private
inventories and two empty turtles, still2000 fuel each. Both requests and all five
physical jobs completed; all count/capacity leases released. The three computers
were shut down and both fixture force-load tickets plus the observer ticket removed.
Local evidence under ignored `dist/live-adaptive/` includes setup, both continuous
state streams, reboot event, final snapshots, world NBT checks, results and cleanup.

Workers used normal turtle, peripheral and rednet APIs. The harness only observed
state and submitted operator commands through the runtime event boundary. No physical
output or worker receipts were emulated. Existing native chunk-loading acceptance is
in0.18; this trial used explicitly assured loading.

## Limits

Unknown item stack sizes remain conservative until physically observed. One recipe
still needs enough private and central space. Only production-linked logical batches
resize; explicit standalone CRAFT contracts keep their requested quantity. Physically
started jobs never shrink to escape a capacity/ownership error. Legacy shared-storage
barriers remain, so this is not acceptance of the full continuous supply pipeline.
