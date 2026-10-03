# Multiworker preparation acceptance — 2026-10-03

Intermediate0.23 evidence for independent supplies, construction traffic and
preparation/build overlap. This does not complete fleet requirements44 or45.
Checkpoint implementation: `b3c4774`. Later preparation retries/fluid sealing were
not installed in this trial.

## Automated evidence

The multiworker snapshot passes712 Lua tests and18 Python tests. Subsequent native
fixes for disconnected supply and checkpoint cost pass79 affected tests and a new
18-test Python run; release generation/check and whitespace checks pass. A full
final current-tree gate remains required before milestone integration.

The actual controller/two-worker simulation uses separate depots, front supply
chests, below-home return buffers and finite8000 fuel each. Both workers survey,
prepare and build. Concurrent preparation/build ownership reaches two; all ten
blocks verify, two foundation holes fill, excavated dirt returns centrally and
private inventories drain. A lost grant and a reboot after physical pickup retain
exact quantities. Focused cases reject endpoint changes, aliases, mismatched workers
and malformed grants. A survey head-on deadlock produced the bounded reserved
navigation detour regression. Broader checks exposed idle couriers occupying reused
delivery stands; managed couriers now return home before completing.

## Native trial

Local PrismLauncher Minecraft1.20.1, world`TESTINMG`, Forge47.4.10,
CC:Tweaked1.120.0, Advanced Peripherals0.7.48r. Controller190, builders191/192 and
inspection-only miners193/194 used a separate rig around `(720..799,300,0..7)`.
Every worker started with8000 finite fuel. The world retained the8 MB ComputerCraft
quota from the earlier preparation trial. No backup was created.

The controller imported a ten-glass schematic at `(740..749,300,6)` and received
`build auto multi`. Shared stock initially held ten glass and no fill. Two
foundation cells were missing at `(740,299,6)` and `(749,299,6)`. Four raised oak
logs obstructed the first/last columns. Operator commands supplied the test terrain
and stone deposits beyond initially empty exploration sectors. Wired storage joined
independent front supply chests and private home-return buffers. Fourteen chunks
were explicitly force-loaded by the operator.

Both builders automatically participated in survey, preparation, construction and
verification. Sampled durable ownership shows two concurrent survey, preparation
and BUILD tasks. All12 preparation regions were verified; construction began in
ready regions before the final preparation region completed. Both miners received
exploration work without manual assignment. This small demand did **not** establish
concurrent mining or workload-based role quotas.

The project reached`built`, reporting **10 correct**, no defects. Independent world
commands confirmed all ten glass, both cobblestone foundations and the cleared upper
log positions. Central storage contained four returned logs. Both builder supply
chests and both home-return buffers were empty. The five sampled mining completion
receipts comprise two empty sectors and three one-cobblestone quota deliveries:
miner193 delivered all three; miner194 completed an empty survey. Two cobblestone
were used for fill; one surplus remained in miner193's depot. No finished fill was
provided by the operator.

All material requests and acquisition groups completed, supply ownership drained,
and all four workers were empty and idle at their own homes. Final finite fuel:
191=7448,192=7424,193=7908,194=7974.

## Failures and recovery

- The front supply modems initially assigned peripheral IDs to the north face even
  though their chests were west. Corrected those fixture modems. No materials or
  worker inventory were changed to bypass supply.
- Disconnected staging caused repeated production requests despite a hardware
  error. The regression fails before the fix. Supply now distinguishes an observed
  stock shortage from an endpoint/ownership error; only a shortage requests more
  production. Existing request history was retained. The trial ended with90 saved
  requests, including the pre-fix excess; it does not claim efficient allocation.
- The accumulated history triggered CraftOS's execution timeout during checkpoint
  saving. Preserved primary/backup/temporary files and staged cargo. Compact native
  encoding plus batched Adler reductions retained the checksum format and reduced
  the checkpoint from roughly254 KB to118 KB. A large legacy-checksum regression
  passes. Controller190 restarted with its original task/supply ownership and the
  build finished. This is bounded recovery evidence, not arbitrary-scale archival.

The test harness submits operator commands at the ordinary runtime event boundary
and observes state; workers use native turtle/peripheral/rednet APIs. Automatic
pause on focus loss was temporarily disabled for the trial and restored afterward.
The fleet was shut down and all14 rig force-load tickets removed. The rig and
finished blocks remain for inspection; the player was not moved for this trial.
Local commands, failed-fixture snapshots, timeout journals, sampled events, final
states, independent world checks and cleanup receipts are under ignored
`dist/live-multiworker/`.

This trial does not establish fluid clearance, fully sealed foundation access,
large schematic scale, dynamic scaling, automatic chunk loading or manufacturing
the supplied glass. Those remain separate required work.
