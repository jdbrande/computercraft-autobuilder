# 0.23.0 automatic site preparation acceptance

Scope: immutable site geometry, bounded surveys and protected preparation,
foundation acquisition and fill, verified construction gates, temporary access
beneath retained structures, and external fluid containment. Dynamic fleet scaling
and the other unfinished fleet requirements continue in subsequent work.

## Automated gate

The final implementation at`01d65e2` passed **748 Lua tests and18 Python tests**.
Release generation,`tools/release.py --check` and`git diff --check` passed.
Later changes in the release checkout contain acceptance documentation only.
The single whole-branch review and its consolidated regression-backed fix pass
are complete; no second review was performed.

Coverage includes transformed footprints, stepped foundations and required air;
terrain/vegetation removal, finite fuel, falling blocks and no-drop excavation;
protected infrastructure, offline owners and vertical worker guards; private
supply endpoints and exact cargo settlement; missing/older sidecar evidence;
fluid retry budgets and retaining walls; optional fresh scanner observations;
and temporary shaft/tunnel opening, hidden support fill, reverse restoration
and final verification. Controller and worker runtime simulations exercise
restarts, lost acknowledgements, post-effect interruptions, finite stock,
shared acquisition and construction through the normal project pipeline.

Preparation exposes verified independent regions to builders. An unresolved
protected or inaccessible position retains its coordinates and reason while
unaffected regions remain usable. Final project settlement also waits for active
preparation, access restoration and containment work between their child jobs.

## Native evidence

All trials used the local PrismLauncher1.20.1 instance, world`TESTINMG`,
Forge47.4.10, CC:Tweaked1.120.0 and Advanced Peripherals0.7.48r, with finite worker
fuel, real turtle/peripheral/rednet APIs and operator-loaded fixture envelopes.
No world backups were created. Detailed reports distinguish operator setup,
recovery, independent observations and cleanup:

- [Multiworker preparation](validation-multiworker-preparation.md): two workers
  surveyed, prepared and built ten glass blocks across twelve regions; miners
  supplied missing fill through the production pipeline. Independent supply and
  return endpoints supported concurrent survey/preparation/build work.
- [Fluid preparation](validation-fluid-preparation.md): separate finite water
  and lava basins, plus cross-region flowing-water stabilization, finished with
  verified structures and returned temporary fill.
- [Sealed-support scanning](validation-sealed-support.md): fresh positive scanner
  observations certified existing generic support beneath retained blocks.
- [Automatic foundation access](validation-foundation-access.md): both one-region
  and nine-region trials filled a sealed center hole beneath a retained3×3 floor.
  Each passed100 independent world checks, consumed one net cobblestone, restored
  excavated ground, and returned its worker home with empty private inventories.
- [External inflow containment](validation-external-inflow.md): the fleet built and
  verified a32-block retaining wall, preserved the outside water source, then
  prepared and built the requested glass. All114 independent world checks passed;
  all164 jobs completed, with exact stock reconciliation and an idle empty worker.
  A controller restart during wall construction preserved containment progress.

## Bugs found and corrected

Native work exposed missing fixture configuration, preparation supply/return
conflicts, movement routing around other workers and excessive checkpoint encoding
cost. Fixes have focused regression coverage and are detailed in the individual
reports and progress ledger. Liquid movement in the simulator was corrected to
match the installed CC:Tweaked implementation before accepting the inflow runtime
case; simulation alone was not taken as native evidence.

The final review found three reproducible issues:

1. A queued unowned build and a new access lease could wait on each other forever.
   Access now drains actual owners, while final ownership admission fences queued
   overlapping work until restoration releases the lease.
2. Corrupt primary evidence could restore a valid unfinished backup against a
   completed root and never progress. Terminal proof is now promoted before root
   retirement, and older unfinished backups reopen a bounded recovery census.
3. Mining-only workers could not request or receive mutation grants. Shared grants
   now apply task-specific enablement. Its restart regression also found a saved
   grant waiting for an unconstructed miner executor; resume now follows engine
   restoration and saved-configuration validation.

Additional regressions prevent premature`built` or retirement between retaining
wall batches, preserve access receipts until both checkpoint copies advance, and
protect cells above and below another worker in either reservation order.

## Limits

Native fixtures were staged and explicitly loaded. They do not establish arbitrary
terrain coverage, automatic infrastructure deployment, large-schematic throughput
or dynamic worker scaling. Chunk-loading compatibility and pose/fuel recovery have
their separate prior acceptance reports. The operator harness submitted commands
at the controller event boundary; terminal input reliability was not tested here.

Preparation remains bounded: region batches, retry counts, access path search and
project margins have explicit limits. One project access lease serializes tunnel
work. Exact schematic cells are retained; generic foundations accept known suitable
support, while retaining walls require the selected nonflammable block exactly.
Scanner absence is not proof of air and a block-name scan cannot prove exact state.
Fluid inflow that exceeds the verified containment envelope remains an explicit
defect rather than a falsely completed region. Optional unsupported blocks and
machine/placement adapters retain their separate requirement coverage entries.
