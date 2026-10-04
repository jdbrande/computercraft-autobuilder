# Fleet requirements progress

Source of truth: [fleet requirements](fleet-requirements.md). Execution guide:
[autonomous mining plan](autonomous-mining-plan.md). Updated 2026-10-03.

## Current work

- Released 0.12.0: remote `main` and annotated `v0.12.0` resolve to `fc15407`.
- Resource dependency/provider milestone integrated at `49dcd9d` and pushed.
- Inventory ownership integrated and pushed at `e66daa5`.
- Fuel distribution/rescue integrated and pushed at `c0d1aa5`:470 Lua/16 Python
  tests and native acceptance including final review regressions.
- Capacity and parallel factory completed:492 Lua/16 Python tests, native
  two-Crafty acceptance and regression-backed final review fixes.
- Capacity/parallel factory integrated and pushed at `345b833`.
- Native schematic support integrated/pushed at `9a27b1b`:508 Lua/18 Python tests,
  both native construction trials and review correction passed.
- Loaded mission compatibility completed:533 Lua/18 Python tests, native chunky
  cross-chunk acceptance, final review fixes and release checks passed.
- Loaded mission compatibility integrated/pushed at `105f2f3`.
- Managed logistics completed:563 Lua/18 Python tests, native two-courier
  restocking, one final review/fix pass and release checks passed.
- Managed logistics integrated/pushed at `d877f95`.
- Interrupted movement/heading recovery accepted:589 Lua/18 Python tests, two
  native interrupted-action/fallback trials and final review fixes. Integrated/pushed
  at `c895b77`.
- Capacity-aware crafting integrated/pushed at `7029c12`:599 Lua/18 Python tests,
  two native pane trials and final review fixes.
- Worker home/unloading and project settlement integrated/pushed at `bb9c41e`:
  623 Lua/18 Python, two native trials, final review fixes and release checks.
- Automatic site preparation0.23 completed:748 Lua/18 Python tests, one final
  review/fix pass and native multiworker terrain, finite water/lava, scanner support,
  within/cross-region hidden access and external-inflow containment acceptance.
  Integrated and pushed at `71b21ed`. Later milestones remain isolated until
  their complete acceptance gates pass.
- Accepted0.24:788 Lua/18 Python tests, native48/48 verified, six workers home
  empty, stock/foundation/workspace reconciliation and cleanup complete.
  High-rate network overload remains documented for later performance work.
- Dynamic scaling0.24 accepted/pushed at`5ec2f40`:788 Lua/18 Python tests and
  native four-builder/two-miner ramp-up,48 verified blocks and final idle drain.
- Mining intelligence0.25 accepted/pushed at`29a3879`:804 Lua/18 Python tests
  and native hazard/retry/observed-yield acceptance.
- Mission fuel forecasts0.26 accepted/pushed at`c77a1a5`:829 Lua/18 Python
  tests and finite-fuel native proactive-refill acceptance.
- Material forecasts/early supply0.27 accepted:846 Lua/18 Python tests, two
  native replacement-acquisition trials including controller/builder reboot.
- Continuous pipeline0.28 accepted:853 Lua/18 Python tests and native overlapping
  placement/acquisition through controller/builder restart and final conservation.
- Worker health0.29 accepted:868 Lua/18 Python tests, final review corrections and
  native read-only hardware/software checks.0.30 single-command enrollment remains
  under its complete gate; native HTTP installation and final-source repair passed.
- Added required scope: dynamic fleet scaling and automatic site preparation,
  including terrain leveling, fill acquisition and verified foundation gates.
  Continue through all rows below in dependency order.
- No external blocker is currently established. Missing implementation is remaining
  work, not an external blocker.

## Requirement coverage

“Partial” means useful existing behavior exists but the complete section is not
accepted. Suggested examples are supported through registered adapters; unavailable
Minecraft hardware must be reported honestly rather than emulated as completion.

| Requirements | Current evidence | Remaining acceptance |
| --- | --- | --- |
| 1–2, 40, 43: complete fleet and hands-off pipeline | Small autonomous chain live-verified in 0.12.0 | Concurrent mixed-material large fleet, broader automatic recovery, safe final return |
| 3: coordination, persistence, physical accounting, capabilities | Existing queues, journals and validated worker telemetry | Extend the same guarantees to all new providers/reservations |
| 4: logical roles | Miners, builders, Crafty workers, furnace controller, managed farms and courier executor | More harvest/processor adapters, fleet-level logistics/rescue; optional scouting |
| 5: automatic registration | Installer, discovery/setup sharing, reconnect and capabilities | Single fleet install flow, equipment/software negotiation, automatic eligibility |
| 6: schematic analyzer | Native/desktop Sponge v2/v3 import, bounded gzip/NBT, transforms and supported-state classification | Supported block entities/fluids/redstone analysis, required tools and broader placement adapters |
| 7: recursive dependency graph | Aggregated nodes, shared stock/surplus, operation edges, bounded expansion; 417 Lua tests | Accepted 0.13.0; preserve during later integration |
| 8: provider registry | Deterministic candidates, availability/preferences, durable acquisition selection | Accepted 0.13.0; preserve during later integration |
| 9: autonomous mining | Accepted 0.12.0 with four live explorers | Preserve during later pipeline integration |
| 10: mining intelligence | Persistent bounded hazards, density, outcomes, retries and native acceptance0.25 | Accepted; preserve during integration |
| 11: fuel management | Configurable fuels, durable stations, automatic refuel and native rescue accepted; budgets deny unsafe trips | Per-mission budget presentation for every role and fleet-wide predictive fuel forecasting |
| 12: logistics network | Registered nodes, reserved parallel couriers, automatic targets/production and native restocking accepted0.19 | Continuous builder/fuel supply integration and broader physical network routing |
| 13: storage abstraction | Durable count claims and physical/available/reserved/transit/expected/project views accepted in 0.14.0 | Native slot capacity and private station ownership accepted in0.16; managed courier integration accepted0.19 |
| 14: continuous forecasting | Per-project physical/reserved/transit/provider forecasts and actual renewable delivery evidence accepted0.27 | Preserve accounting through later provider additions |
| 15: parallel crafting | Two native private Crafty stations with input/output leases, finite batches and restart acceptance | Capacity-based batch sizing accepted0.21; cross-role pipeline integration remains |
| 16: processing network | Furnace lanes and fuel partitioning | Generic machine providers, timing/capacity forecasts and supported processors |
| 17: renewables | Managed trees, crops, column farms with replant/return journals | Provider coverage/reserve policies for registered additional farms |
| 18: builder fleet | Owned regions and movement reservations | Concurrent multi-builder acceptance with independent supply and dependencies |
| 19–20: placement graph/adapters | Basic support, stairs/slabs/logs, doors, panes/fences, ladders/lanterns | Beds, signs, rails, buttons/redstone/plants and supported fluid/tile adapters; cross-region dependencies |
| 21: builder supply | Bounded journaled supply batches | Early replenishment and automatic project logistics/direct delivery |
| 22–23: verification/repair | Physical comparison and explicit repair jobs | Automatic bounded defect scheduling and independent repair-worker acceptance |
| 24: worker states | Heartbeats, task/fuel/pose/errors | Equipment/software health and full recovery-state presentation |
| 25: rescue | Native identity-checked fuel delivery, original-task recovery, offline ownership and journal preservation | Reachable inventory recovery and broader blocked-route recovery missions |
| 26: offline owners | Ownership survives timeout/restart | Extend to new leases and configurable recovery commands |
| 27: chunk loading | Strict bounded coverage, durable stationary chunky claims, native cross-chunk construction and offline-loader refusal | Accepted0.18; preserve during infrastructure/scaling work |
| 28–29: protection/traffic | Protected projects/depots/routes, cell reservations | Global station/farm registration, larger fleet deadlock/routing checks |
| 30–31: priorities/scheduling | Capabilities, dependencies and exclusive jobs | Priority/cost/fuel/chunk scheduling, dynamic roles and simultaneous projects |
| 32–34: monitor, commands, logs | Terminal screens and role/project commands, rotating logs | Monitor fleet dashboard, consistent fleet/project/resource/recovery commands, structured significant events |
| 35–37: messages, duplicates, checkpoints | Existing validation, exact receipts and physical-action journals | Apply and regression-test every new message and side effect |
| 38–39: completion and failures | Verified projects and final inventory/logistics/worker settlement accepted0.22 | Broader bounded automatic retries and actionable project errors |
| 41–42: dependency-ordered milestones | Exploration, dependency/provider graph and count ownership integrated | Implement remaining milestones using existing controller/executor boundaries |
| 44: dynamic fleet scaling | Shared-material explorers and capability-based queues provide partial foundations | Demand/yield/travel/rate allocation, role minimum/maximum counts, bottleneck response, safe idle reassignment and scale-down; simulation and live miners/clearers/builders ramp-up |
| 45: automatic site preparation and leveling | Accepted0.23:748 Lua/18 Python tests, native terrain/fluids/support/access/containment; see validation-0.23.0.md | Preserve during scaling and later integrated acceptance |

## Evidence and discovered bugs

- 0.12.0 permanent report: [validation-0.12.0.md](validation-0.12.0.md).
- Final clean-main release gate at `fc15407`: 406 Lua tests, 16 Python tests,
  release artifact check and whitespace check passed; git status empty.
  Local logs: `dist/release-0.12.0/`.
- Live 0.12.0: controller 100, four miners, crafter and builder, finite fuel,
  staged loaded territory; original 3/3 blocks and follow-up 1/1 verified.
  Full evidence and limitations are in the release report; no claim of natural
  terrain scale, scanner live acceptance or automatic chunk loading.
- Fixed blocked CRAFT resume and duplicate production after released supply;
  regression tests failed before fixes and passed after. Commit `487c1bb`.
- Live harness exposed possible console-event loss during yielding peripheral
  calls. Terminal input reliability remains a tracked runtime recovery item.

## Decisions and authorization

- Ruling: execute natively on milestone branches in the current checkout — user
  authorized autonomous Git choices and continued current-branch work; this keeps
  IDE paths stable. Cost: no separate working-directory isolation; keep commits
  bounded and leave the unrelated `.worktrees/autonomous-production` untouched.
- Ruling: use the source-of-truth milestone order, inserting prerequisite durable
  inventory reservations before parallel physical consumers — double spending
  would invalidate every later fuel/logistics/factory acceptance.
- User explicitly authorized routine commits, merges, pushes, live tests and
  destructive test-world changes. Do not ask routine workflow/design approvals.
  Preserve recovery guarantees in product code even when test fixtures may reset.
- Two pre-existing HEIC photos remain unchanged and excluded locally by exact name.

## Execution log

- Milestone 1 released and independently reviewed; next implementation task is
  provider registry configuration/selection with focused red-green tests.

- Task 9: provider registry/configuration selection implemented. Four focused tests
  passed after the missing-module failure; full Lua suite passed 410/410. Defaults
  preserve legacy providers, preferences are validated, stock/online availability
  guide selection. Runtime provider dispatch and graph accounting remain next.

- Task 10: explicit dependency graph and bounded recipe expansion implemented;
  shared intermediates retain producer dependencies. Focused red-green cases and
  full Lua suite passed 413/413. Node available is original physical stock,
  reserved fuel is explicit demand, and planned output remains separate.

- Task 11: provider routing and `resource ITEM` command pass focused regressions
  and the 417-test Lua suite. Final release-artifact suite is running. Python
  suite passed all 16 using `.venv/bin/python` (system Python skips Lua bootstrap).
  Real test controller is acquiring four cobblestone for four new stone bricks;
  graph separates two initial bricks from planned output. Reboot was necessary
  to load changed eagerly required modules; lazy planner had loaded immediately.

- Milestone 2 final gate: 420 Lua tests and all 16 Python tests passed; release
  artifacts and whitespace checks passed. Independent review found two important
  fallback bugs, both fixed with red-green regressions, plus failed-save rollback.
  Live request produced four new bricks from mined inputs (six total), and a
  fresh post-reboot request delivered two cobblestone with its provider ID saved.
  Independent physical chest inspection confirmed both quantities. Test fleet
  shut down and force-load tickets removed. See [0.13.0 acceptance](validation-0.13.0.md).
- Deferred minor: missing farm/logging workers show generic acquisition waits;
  address with worker-health/status requirements, retaining existing recovery.

- Inventory ownership design selected: durable count grants plus measured
  cumulative receipts, keeping factory exclusivity until independent station
  staging/slot journals exist. Tasks 12–14 define implementation and acceptance.

- Task12 durable ledger implemented: five focused tests passed after missing-module
  RED; full suite 425/425 after correcting a test-registration edit. Atomic claims,
  immutable identities, ordered partial receipts, restart and save rollback pass.
  Runtime factory gates and receipts remain Task13; ledger alone does not yet
  coordinate physical consumers.

- Task13: factory contracts/gates and cumulative withdrawal/output receipts
  implemented. Four new regressions failed before changes; production/runtime/
  logistics focused suites and full 429-test Lua suite passed. Legacy checkpoint
  fixtures now omit modern ledger grants as well as modern jobs. Live furnace
  acceptance is running and has reported actual partial delivery under its claim.

- Task14 initial gate: resource ownership view regression passed; full Lua suite
  430/430, Python16/16 and release artifact check passed. Live furnace/Crafty
  request made four additional bricks from staged raw inputs; both claims showed
  measured withdrawals/deliveries and released. Reboot retained released state;
  independent chest inspection confirmed ten bricks. Final branch review pending.

- Inventory final: 431 Lua/16 Python tests passed after a reproduced yielding-read
  race was fixed with reciprocal observation/action locks. Independent review
  found no additional issues. Fixed live run reached fourteen physical bricks,
  four claims released overall, and test computers/tickets were cleaned up.
  [0.14.0 acceptance](validation-0.14.0.md) records scope and evidence.

- Fuel design/Tasks15–18 selected. Use native reserved-slot refueling, dedicated
  station ownership and measured delivery; retain original stranded-worker task.
  Installed CC1.120 lacks the newer1.121 turtle_storage upgrade, so it is not a
  dependency. Native receiver identification will be verified before rescue code
  selects direct transfer versus temporary-station fallback.

- Task15: configured fuel policy/budget/native refueling tests and the full Lua
  suite passed435/435. Lava containers are retained until a verified depot return
  is possible. Automatic station dispatch remains Task16.
- Native rescue feasibility: turtle107 verified adjacent miner101 through
  peripheral.getID and physically delivered one coal with dropDown; probe cleanup
  submitted. This is hardware feasibility, not completed rescue automation.

- Task16 in progress: eight focused fuel-service tests pass, covering grants,
  partial/restarted transfers, failed checkpoints, offline ownership, missing stock,
  ambiguous observations, shared inventory locks and capacity. A real-module runtime
  simulation refueled an empty turtle to160 through the network and released its
  owner. This is simulated hardware evidence; native fuel acceptance remains open.
- Required scope expanded on 2026-10-03: sections44–45 retain all user requirements
  for dynamic fleet scaling, terrain leveling and automatic site preparation.
  These are mandatory completion gates, not optional enhancements. Existing bounded
  preparation and shared-demand mining do not establish this broader acceptance.

- Task16 complete: 445 Lua tests passed after the remote-trip budget regression
  failed and was fixed. Station deliveries use durable count claims, measured
  capacity, the shared inventory lock and restartable transfer intents. Pending
  refuel work holds workers before mining dispatch; offline consumers retain their
  station. Native station/rescue acceptance remains Task18.
- Task17 started: receiver recovery contract and four failing tests define frozen
  task preservation, measured delivery, consumption after a reboot, changed-message
  rejection, failed-save safety and refusal of uncertain or active movement.

- Task17: receiver freeze/receipt/consumption, station-backed courier dispatch,
  identity-checked partial delivery and return are implemented. All462 Lua tests
  passed, including full runtime original-task recovery through lost receipts and
  controller/recipient reboot. A stale pre-release heartbeat cannot start a second
  rescue, and an interrupted delivery reconciles without manual resume.
- Native fuel trial: depot worker113 reached160 fuel; courier112 delivered two
  coal to stranded111, whose original RETURN_HOME task finished with152 fuel.
  Two live bugs were reproduced and fixed: overhead return hit the station chest
  (side approach now tested), and controller peripheral yields discarded incoming
  release receipts (bounded network collector/main-loop drain now tested). The
  first route was resumed after deployment; a fresh unattended retest on114/115
  is in progress. The initial settled courier returned with462 finite fuel.
- Task18 current: operational fuel status/setup documentation, fresh native
  acceptance, complete release checks and whole-branch review. Dynamic scaling
  and terrain preparation remain required later work under sections44–45.

- Task18 pre-review gate:466 Lua/all16 Python tests, regenerated0.15.0 release and
  release/whitespace checks passed. `fuel` exposes station/worker/recovery status;
  `setup fuel` copies validated controller policy without moving or burning fuel.
  Frozen recipients and unsettled rescues block setup. Unknown cyclic profile
  fields are ignored after a reproducing regression.
- Fresh native acceptance114/115 passed without rescue assignment, fuel transfer
  or task resume by the operator. Original return completed; courier returned;
  all13 jobs completed, both rescues released, seven station claims released.
  Independent world reads matched152/420/160 fuel and conserved the original20
  coal (8 consumed,12 remaining). Live `fuel` status showed all stations2/2.
  Computers110–115 were shut down and27 force-load tickets removed. Evidence and
  scope: [0.15.0 acceptance](validation-0.15.0.md). Whole-branch review next.

- Whole-branch fuel review found three Important defects. Four regressions failed
  first, then passed: unlimited-fuel telemetry registration; default16-coal station
  leaving fuel in Crafty slots; two-coal station stalling below target; and final
  lava-container cleanup before managed release. Refuel now pulls one item at a
  time and returns containers safely; durable finite batches release/replenish until
  the measured target. Full suites and native16/2-coal station retest are running.
- Final fuel gate:470 Lua and16 Python tests passed; release artifacts and whitespace
  verified. Native default16/small2 station retest completed automatically: both
  workers160→1040 fuel, one/six batches, empty turtle inventories, all jobs complete.
  Final review defects are regression-covered; integration into main is next.

- Task19: six capacity regressions failed before implementation and now pass.
  Claims allocate concrete slot quantities using native limits; exclusive station
  ownership survives reboot, and failed multi-inventory saves roll back atomically.

- Task20: private station validation/capability, private-buffer Crafty execution,
  durable collecting state and suppression of premature central-stock credit pass
  five new regressions, including worker reboot. Full suite:481 Lua tests passed.

- Task21: two real runtime Crafty modules execute private finite batches concurrently.
  Central staging/collection use journaled transfers, count claims and concrete output
  slots; partial transfers, three interruption points and lost acknowledgements pass.
  A failing regression found that private staging starved an older furnace owner;
  waiting batches now yield execution so the shared owner can drain. Full suite487
  passed; an additional short-stock/two-batch regression also passes. Native120–122
  acceptance is running with48 requested stone bricks and64 starting stone.

- Task22 native acceptance: controller120 and Crafty121/122 completed48 stone bricks
  from64 stone in six automatically scheduled batches, with two workers concurrent.
  Controller/worker reboot during production needed no resume or reassignment. World
  inspection confirmed48 output,16 remaining stone, empty private chests/turtles,
  unchanged finite2000 fuel and all count/capacity leases released. Final status
  retest, full release gate and review are in progress.

- Native follow-up reached64 total bricks from the original64 stone; all eight jobs
  completed, both workers idle, all count/capacity leases released. `factory` showed
  32 collected per station, rates0.60/0.55 per second on timed follow-up batches.
  Computers120–122 are shut down; observer/station force-load tickets removed.
  Final pre-review gate:489 Lua/16 Python tests, regenerated0.16.0 release/check and
  whitespace validation. Whole-branch review is next.

- Parallel-factory review found two Important recovery defects and one minor
  configuration alias defect. Three regressions failed then passed: saved private
  inventories cannot become shared stock; a crash cannot switch a partly assigned
  private operation to legacy crafting; legacy endpoints cannot alias private
  stations. Final full-suite gate is running. Automatic smaller batches for
  first-time high-yield recipes remain tracked with dynamic crafting scaling.

- Task22 final gate:492 Lua/16 Python tests, release generation/check and whitespace
  checks passed. Reviewed fixes are complete; integrating0.16 and continuing0.17.

- Task23: bounded native gzip decoder passes four new RED→GREEN cases and the
  full496-test Lua suite. Pinned LibDeflate source SHA verified; license retained.
  CRC/header/size/trailing-data checks and cooperative expansion bounds are covered.

- Task24: typed NBT/Sponge v2/v3 conversion passes seven new RED→GREEN cases,
  native/Python differential checks, full503 Lua tests and18 Python tests. Required
  air/states/offsets and recomputed quantities survive; unsupported metadata is
  explicit. Import command integration and native acceptance are next.

- Task25: four import/runtime regressions failed then passed. Single-snapshot import
  fixes existing JSON validation/save races. Repeated native shorthand/reboot does
  not duplicate work. Full507 Lua/18 Python and release checks passed.
- Native130/131 acceptance: gzip v3 input built/verified3 blocks plus cleared air;
  a16-block follow-up survived controller reboot, all16 independently confirmed.
  Repeating shorthand retained7 jobs/2 requests. Both projects built, worker idle
  with1791 fuel and one recovered dirt. Final home return/unload remains required.
  Test computers shut down; observer/rig force loading removed. See
  [0.17 acceptance](validation-0.17.0.md). Whole-branch review next.

- Final schematic review: one Important stored-DEFLATE buffer-growth issue. A
  regression failed at622546 working bytes, then passed after draining all full
  slices. Stored→compressed backreferences remain correct. Full508 Lua/18 Python
  and release checks passed. Native8MiB inflation took2.242s with383 yields and
  correctly refused a1MiB bound. Integration follows; no requirement is dropped.

- Task26: six coverage geometry/provider/checkpoint regressions failed then passed;
  full514 Lua tests passed. Strict policy, actual chunky detection, bounded chunk
  envelopes and durable provider claims are ready for dispatch integration.

- Task27: dispatch, movement, telemetry and immutable grants pass12 focused runtime
  regressions. Full525 Lua tests passed before the final opt-out regression/fix;
 18 Python tests passed. The final full suite includes that additional case.
  Existing hardware simulations explicitly declare their loaded terrain. Failed
  queue checkpoints roll back ownership and geometry; physical recovery keeps its
  owner and requires assured coverage before a missing historical grant can move.

- Task28 native: anchors140/141 kept distant chunks64,64 and65,64 loaded after
  vanilla fixture tickets were removed. Builder143 placed/verified4 bricks across
  the boundary in55.48s with a controller142 reboot. Uncovered chunk66,64 never
  acquired a worker. Offline141 blocked a new verification; reconnect resumed it
  with4 correct cells. Final leases released; builder1906 fuel, anchors2000 each.
  Fixture shut down and physical anchors removed; AP ticket expiry is asynchronous.
- Task28 pre-review gate:529 Lua/18 Python, release0.18 generation/check and
  whitespace checks passed. Operator chunk status/setup and migration guide added.

- Task28 final gate:533 Lua/18 Python tests passed, release generation/check and
  whitespace validation passed. Review regressions cover finite exploration
  geometry, stationary legacy effects and unknown-pose execution. Delayed GPS
  restores the prior phase before recovery. Independent world checks confirmed
  both AP tickets expired; observer force loading removed. Integrating0.18 and
  continuing required logistics without a milestone pause.

- Task29: five node/protection regressions failed first, then passed. Full suite538
  Lua tests passed. Registered stocks and private courier stands are protected;
  active endpoint identities survive restart and configuration cannot adopt an
  orphan private lease. Task30 reserved transport execution follows.

- Task30:552 Lua/18 Python tests passed. Finite private-buffer hauls atomically
  reserve stock and final slot capacity, stage only the requested mixed-stock item,
  and credit destination stock only after measured collection. Two actual courier
  runtimes pass concurrency, both reboots, lost acknowledgement and full-destination
  recovery with finite fuel. Regression fixes also cover coverage of registered
  remote stock and shared legacy/fuel consumer isolation. Native acceptance and
  automatic restocking remain Task31.

- Task31 restocking simulations pass: desired stock subtracts inbound commitments,
  protects source targets, ranks sources and requests production once across restart.
  Native150–152 initial trial exposed pickup selection sending a courier toward
  another parked worker. A RED→GREEN regression now chooses nearest free pickup
  and drop buffers. The staged rig was reset with independent lanes; retest running.

- Task31 native acceptance: one automatic48-stone restock, six8-item batches,
  two concurrent couriers, controller and settled-action worker restart, and
  disconnected destination collection/reconnect. Independent world reads:16 stone
  plus7 dirt at source,48 stone at destination, all buffers/turtles empty, finite
  fuel1748/1892. All count/capacity/chunk leases released; no extra work.
  Native fixture setup corrections and interrupted-move limitation are recorded in
  [0.19 acceptance](validation-0.19.0.md). Pre-review gate557 Lua/18 Python and
  release/diff checks passed; final whole-branch review follows.

- Task31 final review: four Important findings fixed with six RED→GREEN cases.
  Unclaimed worker preferences no longer block older factory owners; grants recheck
  worker availability. Forecasting respects protected fuel and held stock, disconnected
  unused buffers are skipped, and unregistered factory output routes block production
  with actionable status. Final563 Lua/18 Python, release generation/check and diff
  checks passed. Native trial predates these admission fixes. Integrating0.19 and
  continuing movement recovery without a milestone handoff.

- Task32:571 Lua tests passed. GPS only reconciles pending translations at their
  journaled endpoints; unexpected fixes retain ownership and evidence. Interrupted
  turns require heading recovery. Failed persistence restores the journal. Actual
  courier runtime recovers a post-effect upward interruption and delivers9 items
  exactly once; paused/unrelated blocks are preserved. Regression also fixed disabled
  worker automation executing a saved task and retained saved chunk boundaries after
  policy opt-out. Atomic heading-probe claims are the next implementation step.

- Task33:581 Lua/18 Python tests passed. Atomic origin-plus-four-neighbor claims
  reject conflicting workers, regions, protection and missing coverage. Heading
  probes journal before one physical move, derive direction only from GPS, return
  to origin and retain claims until acknowledged settlement. Actual courier runtime
  recovers turn/probe reboots and lost grant/ack packets, delivering9 items once.
  Unit tests cover post-backtrack reboot, GPS outage/mismatch, fuel, obstruction,
  pause, disable and failed persistence. Native GPS acceptance follows.

- Task34 native: real GPS hosts162–165 restored courier161 after post-effect reboots
  on up, turn, forward probe and backtrack, plus controller160 restart. GPS absence
  retained ownership for at least10 seconds before hosts started. One9-stone automatic
  haul completed in39.30s. Independent world reads: source55 stone+7 dirt, destination9
  stone, empty buffers/turtle,1978 finite fuel. Claims released; computers shut down
  and force loading removed. No operator pose/stock/fuel correction. Whole-branch
  review and final release gate follow; all broader requirements remain active.

- Final0.20 review found four Important fallback/configuration defects. Regressions
  reproduced then fixed missing controller claims, cleared worker backtrack heading,
  mining-only control refusal and absent-depot crashes. Additional cases protect
  settlement receipts, telemetry cleaning and delayed old-controller grants.
  Native fallback retest delivered another9 stone after corrupting only both primary
  checkpoints at exact recovery boundaries: controller backup had no claim; worker
  backup held return-stage evidence. Final source46stone+7dirt/destination18stone,
  empty buffers/turtle,1936 fuel. Native fixtures shut down and tickets removed.

- Final0.20 gate:589 Lua/18 Python tests; release generation/check and whitespace
  validation passed. Four Important review findings fixed with regressions; no
  re-review. Both native rigs were shut down and all test loading tickets removed.

- 0.21 implementation: read-only capacity previews reuse the native allocator and
  cache sizing observations. Atomic grants size ingredient/output contracts before
  staging; only granted intervals count as production coverage. An unusable station
  cannot withhold work from another. Old unstarted stock-only batches retire with
  cancelled ledger IDs; owned journals remain unchanged.
- Pane stall and unclaimed worker pinning regressions failed before fixes. New cases
  cover heterogeneous capacity, old checkpoints and atomic-save rollback. Initial
  full gate:595 Lua/18 Python passed; release0.21 generation/check passed. A further
  failing status assertion restored actionable capacity errors for unclaimed work.
- Native pane trial is running on reused isolated controller120/Crafty121–122 with
  24 glass, no pane sample and2000 finite fuel each; no world backup.

- Native0.21 accepted:24 glass→64 panes without an output sample, then24 more glass
  →128 total panes with concurrent Crafty121/122 and controller/worker reboot.
  Independent world reads confirm exact counts, empty private/turtle inventories,
  2000 fuel each and released claims. Rig shut down and loading tickets removed.
  Permanent report: [validation-0.21.0.md](validation-0.21.0.md). Final branch review next.

- 0.21 final review found two Important and one Minor issue: yielding-observation
  worker race, offline legacy claim starvation and lowered maximum ignored on reboot.
  All reproduced RED→GREEN; a fourth regression covers pause during observation.
  Final eligibility checks precede atomic grant; legacy retirement precedes station
  availability; only unclaimed work adopts a lowered maximum. Full gates running.
- Next dependency is safe worker home/cargo return and project settlement, needed
  before debris-producing large site preparation and safe fleet scale-down.

- Final0.21 gate:599 Lua/18 Python tests passed, release/check and whitespace clean.
  All final review findings fixed; native evidence recorded. Integrating then
  continuing home unloading and project settlement without a handoff pause.

- 0.22 Task38 foundation: bounded nonreserved cargo manifests and strict protocol
  cleaning; journaled home travel/drop executor uses existing R.delta and preserves
  fuel/tools. Seven home tests and network tests pass, including partial drops,
  post-effect restart, ambiguous reserved-slot mutation and failed receipt saves.
  Existing runtime/logistics focused suites pass. Controller return collection and
  project completion gate are in progress; no native acceptance claimed yet.

- 0.22 Task39: controller returns reserve private/central capacity and output-only
  counts atomically, retain the worker through exact collection, and acknowledge
  only afterward. Runtime mixed-cargo test passes both post-drop and post-collection
  restarts, lost acknowledgement, partial transfers and protected fuel slots.
- Initial Task39 full gate615 Lua/18 Python passed. Additional RED→GREEN regression
  prevents shared factory/supply observers from starting while return cargo is owned;
  existing private return collection and its runtime regression pass afterward.
  Grant rollback, yielding-worker/cargo changes, node rebinding, loaded central
  geometry and exact acknowledged receipt tests pass. Project barrier follows.

- Task40: final VERIFY now enters settling; linked production/supply/mining actors
  persist across phases and pruning. Claims, receipts and fresh home/empty telemetry
  gate completion; compatible empty durable reassignment releases an unclaimed return.
  Project and full-chain runtime fixtures now exercise real storage/home settlement.
- New RED→GREEN cases cover paused pending collection reconciliation and pause before
  home job creation. Native171 returned5 stone+3 dirt after post-drop/post-collection
  reboots, retaining reserved2 coal+pickaxe and1988 fuel. Central/private world counts
  match;170/171 shut down and all five fixture/observer loading tickets removed.
  Permanent evidence: [0.22 acceptance](validation-0.22.0.md). Final gates in progress.

- Task40 complete gate:622 Lua/18 Python passed; release0.22 generation/check and
  whitespace clean. Final whole-branch review/fix pass follows before integration.

- Second native0.22 trial: two stone blocks built/verified, settling observed, controller
  rebooted, spare2 stone unloaded before built in38.48s. Independent world counts:
  central7 stone+3 dirt, empty home buffer, reserved coal/pickaxe retained,1952 fuel,
  no held claims. Rig shut down and all loading tickets removed again.
- Final0.22 review found two Important settlement races: completed unrelated tasks
  falsely qualified as reassignment; completed home evidence was ignored after newer
  unrelated cargo. Both reproduced RED→GREEN and fixed; stale evidence now requests
  a new return, and durable fresh evidence survives subsequent offline telemetry.
  Final gates:623 Lua/18 Python passed, release/check and whitespace clean; no second review.

- 0.23 design/Tasks42–45 now cover the complete required preparation pipeline.
  Starting transformed footprint/foundation planning; dynamic scaling44 remains the
  next dependent requirement, followed by all remaining source-of-truth scope.

- Task42 geometry: four RED→GREEN cases cover all16 rotation/mirror combinations,
  exact air/state lookup, stepped foundation validation, immutable source copies,
  bounds and lazy clipped regions for262144 cells. Survey/ownership integration is
  next; no physical site-preparation completion is claimed.

- Task43 survey foundation: bounded SURVEY_SITE contracts and immutable cumulative
  observations now run through real controller/worker modules; both reboots and lost
  completion acknowledgement pass with finite fuel and zero dig/place actions.
  Tests reject invalid/changed observations, preserve progress on failed saves and
  cover pause, surface/empty columns and exact transformed geometry. Regional project
  scheduling, adaptive access, protection and physical preparation remain in progress.

- Survey foundation gate at69651ea:634 Lua/18 Python passed, release/check clean.
  Shared site protection is now under test: registered infrastructure/other projects,
  offline worker positions, active regions/routes and physical-change reservations.
  Regressions reject unplanned/protected targets, distinguish movement/action grants,
  restore cells after failed saves and allow clear overhead transit above owned work.

- Task43 project surveys now keep four active region payloads, save observations in
  separate checked region files before shrinking the controller checkpoint, and
  create higher immutable attempts for obstructed access. Root-save and evidence-save
  regressions preserve receipts without duplicate completion. Actual project runtime
  covers pause/resume, controller restart and read-only footprint/workspace coverage.
- Ownership regression fixed admission over offline workers, pending traffic cells
  and owned mining routes; survey completion now first exits to overhead clearance.
  The preceding protection/exit full gate passed643 Lua tests. Final combined survey
  gates follow. General physical preparation and scaling are not yet accepted.
- Combined Task43 survey foundation gate:649 Lua/18 Python tests passed; release0.23
  generation/check and whitespace checks passed. Native-hardware-style runtime also
  verifies a real obstructed overhead cell triggers a higher immutable survey job.
  No new live Minecraft acceptance is claimed for this intermediate foundation.

- Task44 physical batch foundation: PREPARE_REGION uses the existing construction
  executor with controller mutation reservations. It preserves matching planned
  cells and suitable support, clears supported terrain, records exact protected or
  inaccessible targets and continues unaffected cells. Side inspection can fill
  beneath a retained floor. Completion first leaves the work interior.
- New physical evidence tests reconcile no-drop vegetation and falling replacement
  excavation; fill journals reject unrelated inventory changes. Actual runtime
  covers post-dig/post-place worker and controller restarts, lost acknowledgement,
  finite fuel and exact two-block fill. A RED→GREEN runtime regression fixes a
  denied mutation waiting forever instead of recording its blocker.
- Full project excavation/fill scheduling, fill shortages/debris return, fluids and
  final preparation gates remain unfinished; these batch tests are not native
  Minecraft acceptance or completion of requirement45.
- Physical batch foundation gate:660 Lua/18 Python tests passed; release0.23
  generation/check and whitespace checks passed. Continuing bounded survey-derived
  work planning and full project integration on the same milestone branch.

- Survey-derived batches now preserve planned states and explicit air through stepped
  foundations, fill observed low terrain and verify foundation/clearance separately.
  Stable foundation placement displaces water/lava with exact restart receipts;
  draining/containing flowing fluids for clearance remains unfinished.
- `build level` runs survey→excavation→debris return→fill→verification through real
  controller/worker modules. Its runtime regression preserves a partial floor, clears
  a mound, fills low supports and survives controller restart without operator work.
  Scheduler regressions bound active work, select unreserved fill, require durable
  debris settlement and allow independent regions to finish around a blocked region.
- Region report pruning now advances the evidence backup before deleting root task
  receipts. A failing evidence write retains the worker report; primary corruption
  subsequently recovers consumed progress from the backup. Full gates are running.
- Survey-derived leveling service gate:668 Lua/18 Python tests passed; release0.23
  generation/check and whitespace checks passed. Committing this intermediate
  service and continuing evidence recovery and normal per-region build gates.

- Region evidence recovery retains all physical task owners, waits for fresh cargo
  acknowledgement/central return and then surveys again. New recovery epochs prevent
  completed work IDs from being reused. Runtime deletion of both region files during
  excavation still finishes leveling with exactly one dig and two fills after reboot.
- A regression reproduced an older controller root stranding a completed worker even
  though its region file had consumed the receipt. Region evidence now retains the
  bounded owner/progress/time receipt and reconciles only after fresh worker telemetry
  no longer claims that task. Invalid prepared markers with unresolved defects are
  rejected. Preparation metadata is refused on unrelated task types.

- Normal build/start now run preparation automatically and gate structural regions
  on their own foundation/workspace evidence. Independent verified regions build
  around a distant protected obstruction; air-only sources do not create foundations.
  Preparation tasks remain separate from structural phase counts, and pause/resume
  includes both. Missing completed proof reopens a bounded census without losing
  active owners or double-counting regions (two new focused recovery cases pass).
- Retirement regression reproduced leaked sidecar evidence; streamed project cleanup
  now removes it after checkpoint backup advancement. A repair regression reproduced
  reuse of stale site proof after ground changed; fresh repair surveys are under test.
- Fixed-deposit and both scanner/inspection-only full production chains pass with
  actual supporting terrain added to their fixtures. Supply and settlement fixtures
  now retain their original fault boundaries after normal preparation. Full combined
  gates follow; no new native Minecraft acceptance is claimed yet.

- Repair resurvey now passes after a foundation is removed between runs. Inspection
  beneath retained floors uses reachable side/below stands; a fully sealed support
  remains an explicit inaccessible defect, with zero digging or placement, rather
  than being certified from the floor above. Automatic access excavation remains
  part of the unfinished general preparation work.
- The Python gate found an ignored macOS `.DS_Store` being decoded by the installer
  test's simulated HTTP fixture. The fixture now serves manifest-listed paths only,
  with synthetic binary metadata coverage. All18 Python tests pass again; the local
  metadata file was left untouched.

- The combined Lua gate reached the legacy first-build shortcut and exposed its
  assumption that `build start` immediately enters construction. A failing handoff
  regression now transfers automatic continuation to the project as soon as start
  succeeds. Pilot fixtures include existing foundation terrain and a finite6000
  fuel allowance for added survey travel. Focused pilot validation is running;
  the interrupted full gate is not counted as passing.

- Shared mutation protection now reaches ordinary construction/repair and both miner
  modes. Workers fail closed without a mutation grant. Controller grants derive door
  upper halves from immutable block states and reserve both cells atomically; new
  tests reject offline occupants, protected upper cells, territory escape and failed
  checkpoint promotion. Mining grants cover only owned areas/routes, preserve exits,
  and refuse other preparation work or registered infrastructure (55 focused tests).
- Enabling these grants exposed a finite-fuel regression: waiting at the placement
  stand recalculated an already-completed outward route and sent the builder home.
  The existing exact-three-coal runtime case reproduced it. Mutation waits now retain
  the route fuel budget while the turtle remains at the granted/requested stand;
  the focused regression is running. Planner-side protection and other roles remain.

- The exact-three-coal runtime regression passes after the mutation-wait fuel fix.
  Exploration now uses shared depot/fuel/farm protection and filters only boxes
  outside its search envelope before applying the128-box limit. Relevant boxes are
  never truncated. Two failing planning cases now pass, including140 distant
  projects; the combined protection/mining/exploration set passes73 tests.
- A legacy exploration fixture had no declared exit through the newly protected
  home access envelope. It now declares its actual clear adjacent exit, preserving
  the original partial-delivery/reboot test. Pilot fixture terrain now matches only
  the selected pilot origin, preventing the other fixture's foundation from becoming
  an artificial obstruction. Pilot structural pause/supply fault limits include the
  preparation phase; these longer runtime cases are still under validation.

- All16 expanded first-build tests pass, including the preparation handoff, finite
  fuel, structural pause/reboot and stock-only supply failures. Both exploration
  construction variants pass with shared mutation grants. Chunk-only stationary
  work now waits for a separate mutation grant while preserving an existing intent.
- An additional full-chain fill shortage case reproduced a real over-request: the
  worker counted an uninspected but already suitable support as another fill item.
  It built successfully but settlement waited for the unnecessary acquisition.
  Preparation now requests only its observed missing cell; the focused regression
  fails against the prior executor (expected1, got2) and passes with the fix. Full
  acquisition-to-settlement validation is still running.
- New failing admission coverage also proved a preparation check could become stale
  during chunk admission. Both enabled and disabled chunk paths now recheck proof
  immediately before saving a new structural owner; owned retransmissions retain
  their original contract. Focused protection/chunk suites pass.

- The additional-fill chain exposed a second race: a fixed miner's final completion
  arrived after its production consumer had already taken the delivered stock.
  Production-created mining now records its consumer and accepts that consumer's
  durable acquired-stock proof, tied to the original mining root and target. Manual,
  unrelated, unconfirmed and smaller-demand consumers retain live-stock checks.
  The new restart regression failed before the fix; focused mining/production tests
  and the full fill→production→build→settlement chain now pass with exactly five
  cobblestone deposited, four smelted and one used for foundation fill.
- Current combined gate: all18 Python tests and release artifact checks pass; the
  full Lua suite is running. A separate native preparation rig180–182 is being
  brought up; its first configuration reused the supply chest as a private return
  buffer and was correctly rejected. Separate front supply and below-home return
  inventories fix that fixture error; no native acceptance is claimed yet.

- Native preparation trial1 surveyed the uneven footprint, excavated dirt and
  preserved controller ownership across a reboot during debris return. It then
  exposed fill selection choosing two returned dirt blocks for three missing
  support cells despite only a cobblestone miner being registered. Acquisition
  correctly reported no eligible dirt worker. A new failing service regression
  now passes with selection comparing available stock to the bounded possible
  fill volume and checking replenishment eligibility. Actual requested quantities
  remain inspection-driven. The isolated candidate passes the site-service suite;
  the main full gate continues on the preceding unchanged code snapshot.
  Failed-trial evidence is preserved under ignored `dist/live-site/trial-1/`;
  the dedicated rig was reset for a fresh candidate trial, without supplied fill.

- Native trial2 reached the default1 MB computer disk quota while checkpointing
  debris settlement. Product journals were preserved and no cargo was manually
  credited. The test world's computer quota is now8 MB; a world reload is needed
  to activate it. General disk-footprint/archival handling remains an unfinished
  fleet requirement, and this trial will not claim operation within the old quota.
- Automatic final repair now passes two new RED→GREEN runtime cases: a missing
  final block is repaired once across restart while matching blocks remain intact;
  repeated external damage stops after three rounds with exact final defects. Each
  round persists its bounded prior report and fresh survey generation. Explicit
  verification stays read-only. Broader project regressions are running.

- The complete pre-fill-selection/automatic-repair Lua snapshot passes694 tests;
  all18 Python tests pass. Subsequent fill/provider changes pass73 focused tests,
  and both new automatic-repair runtime regressions pass. The expanded project
  suite is completing separately; the full current-tree gate remains required
  before final milestone acceptance. Release generation/check and whitespace pass.
- Trial2 resumed its saved preparation after the world reload with8 MB disk quota.
  The controller selected cobblestone and automatically assigned explorer182 for
  the fill shortage. Builder181 was restarted after its first physical fill while
  waiting for that delivery. Native completion is still pending.

- Expanded project runtime suite passes34 cases, including both new automatic
  repair cases. Current Python rerun passes18; focused affected suites pass73.
  Normal pipeline, shared construction/mining grants and these regressions are
  ready for a checkpoint commit; the remaining0.23 work continues on this branch.

- Native uneven-terrain trial2 reached `built`: three glass blocks verified, three
  cobblestone fill cells independently confirmed, two dirt cleared/returned, both
  workers idle at home with5398/5936 finite fuel. Supply, return and mining deposit
  chests are empty. The rig was shut down and test force-load tickets removed.
  See [intermediate site acceptance](validation-site-preparation.md) for setup,
  the fill-selection bug,8 MB quota requirement, restarts and exact scope limits.
- Managed harvesting now requires controller mutation grants for both digging
  and replanting. Its own registered crop cells are authorized; soil/column bases,
  foreign farms, offline workers and concurrent ownership remain protected. New
  permission tests exposed an older soil-inspection movement wait loop. The worker
  now persists that observation before returning above the crop; a regression
  reproduces independent movement/work grants and restarts between those stages.

- Shared mutation protection now includes legacy PREPARE_SITE canonical waypoints.
  Its own declared access above the depot may be cleared without exempting the
  container, other workers' homes, fuel infrastructure or arbitrary nearby cells.
  New failing guard/access tests pass, as do renewable and logistics-node checks.
  Legacy native-style pilot regression is running with the added grants.
- Renewable admission also excludes overlapping active farm columns before ownership,
  preventing two assigned workers from indefinitely denying each other's grants.
  Focused renewable/protection/coordination/production coverage passes90 cases;
  additional chunk/runtime/provider checks pass.

- Legacy automatic clearing→normal preparation→construction passes its actual
  controller/worker restart regression with mutation grants. The shared protection
  step now covers construction, mining, legacy clearing and managed harvesting.
  Focused site/protection/renewable/exploration/node coverage passes60 cases, and
  chunk/runtime/provider coverage passes70. Release generation/check and whitespace
  checks pass; no new native harvesting claim is made.

- Multiworker acceptance exposed a configuration prerequisite: supply currently
  targets one global chest at each worker's depot, while home returns need private
  buffers. Sharing the physical depot would let idle workers block later returns.
  Task45 now includes registered per-worker supply endpoints using the existing
  journal and lease. Dynamic quotas and fluid/sealed-foundation work remain required.

- Registered per-worker supply endpoints now retain endpoint identity through
  controller staging recovery and worker grants, reject shared/private inventory
  aliases and refuse mismatched worker depots before staging. A failing regression
  caught configuration failures creating replacement production requests; that
  path now waits without manufacturing stock. Supply remains one durable batch at
  a time; independent workers continue construction after their pickups.
- The new actual two-builder simulation exposed a head-on survey route deadlock.
  Navigation now reuses bounded pathfinding after confirmed worker-occupancy
  denial, persists its detour across reboot and reserves each physical step.
  Focused restart/protection/fuel/coverage checks pass. The integrated two-builder
  case is still running; no concurrent construction acceptance is claimed yet.

- The two-builder runtime passes: both workers survey, prepare and build independent
  regions; preparation/build ownership overlaps, all10 blocks verify, two missing
  foundations fill, and two excavated dirt return centrally. Separate supplies
  survive a lost grant and controller/worker restart after physical pickup. Both
  workers finish empty with finite fuel and all private chests/supply ownership drain.
- That run exposed depot headings being omitted from cleaned telemetry. Headings now
  validate and survive transmission, allowing front-facing station identity checks.
  Broader routing validation exposed an idle courier occupying a reusable delivery
  stand. Managed couriers now return home before completion; the two-courier
  partial-delivery/restart case passes with explicit final-home assertions.

- The multiworker snapshot passes all712 Lua tests and18 Python tests. Native rig
  190–194 is in progress with two builders, two miners, ten glass targets, four
  raised logs and two missing foundation cells. The staged test envelope is loaded;
  this is not dynamic role-quota acceptance yet.
- A fixture error assigned the front supply modems' peripheral IDs to the wrong
  face. Corrected the modem NBT without adding materials. That disconnection exposed
  repeated production requests for a hardware error: supply now returns an explicit
  observed-stock-shortage signal, and only that signal can request production.
  A RED→GREEN disconnect/reconnect regression confirms no spurious requests.
- The accumulated pre-fix request history exposed CraftOS's execution timeout while
  saving a253 KB checkpoint. Compact native serialization and batched Adler modular
  reductions reduce the same checkpoint to118 KB without yielding in transactions.
  A large legacy-checksum/compact-encoding regression passes. The native controller
  resumed its original saved ownership and staged cargo; journals were not reset.
  These two post-snapshot fixes pass79 focused regression/coordination/logistics and
  managed-runtime cases. A full final current-tree gate remains required.

- Checkpoint commit `b3c4774` records independent supplies, traffic detours, courier
  home return and the two native-discovered recovery fixes. Current work adds
  bounded preparation retries: fresh region surveys/work epochs after failed
  verification, at most three retries, preserved defects and settled prior owners.
  Focused service tests and an actual foundation-change/reboot/build runtime pass.
  Native multiworker preparation has verified10/12 regions and construction began
  in a ready region while remaining preparation continued. Acceptance is pending.

- Native multiworker trial reached`built` with10/10 correct, all12 prepared regions,
  two concurrent builder/preparation owners, four logs returned, two mined fill
  cells and one retained cobblestone surplus. All workers returned empty; final
  fuel191/192/193/194=7448/7424/7908/7974. Both miners participated, but only193
  delivered material and mining was not proven concurrent. Independent world checks
  and cleanup passed. Permanent scope/failures: [multiworker acceptance](validation-multiworker-preparation.md).
- Fluid sealing now has failing-then-passing executor, geometry and service tests:
  replace only fluid cells with stable temporary fill, preserve dry blocks/air,
  retain placement journals across reboot, then clear the entire sealed region.
  Explicitly protected fluids remain untouched. Runtime pocket drainage and
  cross-region/external-flow containment remain in progress.

- The combined preparation retry service/project set passes49 cases. Fluid executor,
  geometry and orchestration checks pass; actual runtime cases drain finite water
  and lava flows, recover a reboot after sealing, clear the temporary block and
  build/verify both glass cells with exact placement/dig counts. Native isolated
  basins200/201(water) and202/203(lava) are now running with finite fuel and supplied
  reusable cobblestone. No native fluid acceptance is claimed yet.

- Both native finite basins reached `built`; independent commands confirmed all48
  clearance cells (four glass,44 air), exactly16 reusable cobblestone returned per
  network, empty private chests and idle home workers. Final fuel201=7416,203=7348.
  All four computers shut down and12 test tickets removed. Permanent evidence and
  scope: [finite fluid acceptance](validation-fluid-preparation.md). Operator-built
  containment means external-flow/cross-region drainage remains unfinished.
- Fresh optional scanner proof now covers generic support sealed below retained
  structure, after inspection approaches fail. Missing/fluid observations do not
  certify support, and failed tool restoration retains the task without a receipt.
  The new regression failed before implementation;51 affected tests pass. Native
  retained-floor scanner acceptance is starting; missing sealed support still needs
  an automatic access/fill solution.

- Native sealed-support acceptance passed: four fresh scanner observations across
  fill/verification, two retained glass,60 independently confirmed stone cells,
  restored pickaxe and scanner slot, unchanged fill stock and home-idle worker.
  Fuel7416→6658. Cleanup and pause-setting restoration passed. Permanent evidence:
  [sealed support acceptance](validation-sealed-support.md).
- A delayed neighboring fluid-source regression reproduced a region remaining
  blocked after its local retry limit even once the source was removed. One bounded
  reconsideration pass after all initial region owners drain now resurveys those
  fluid failures. The17-case service suite passes, including controller recreation,
  failed checkpoints and permanent inflow stopping after eight preparation attempts.
  Actual cross-region runtime/native acceptance is still required. The earlier full
  suite snapshot remains running; it does not include this later reconsideration.

- The fluid/scanner full snapshot finished with721/722 Lua tests passing. Its only
  failure was the two-builder test's incidental timing assertion: both workers built
  all ten correct blocks, but tiny two-block jobs completed sequentially as regions
  became ready. A diagnostic reproduced that schedule. The test now deliberately
  delays one builder's startup and requires the other to receive independent BUILD
  work before releasing it; overlap remains mandatory. That regression and a wider
  actual cross-region fluid runtime are running. The18-test Python suite passed.
  A fresh full gate is required after these fixes; this snapshot is not accepted.
- Native cross-region basin204/205 is running with nine glass targets, a far-end
  water source,32 reusable cobblestone and12000 starting fuel across two preparation
  regions. Six chunks are operator-loaded. No acceptance result is claimed yet.

- The delayed-source actual runtime passed: nine glass across two preparation regions,
  exhausted initial fluid retries, later source sealing, one reconsideration pass and
  controller/worker reboot all complete with nine verified blocks and no supply lease.
- The two-builder timing regression now passes with a slow departure from a private
  depot after supply settlement. An initial fixture attempt held a turtle in the work
  area and correctly blocked another worker's destination; the corrected fixture
  holds only at home. Both preparation and BUILD overlap remain required assertions.
  A fresh full Lua gate is running;18 Python tests and release/diff checks pass.
- Began missing-support access geometry. A failing-then-passing case plans a bounded
  connected shaft/tunnel under a retained3×3 floor, refuses exterior/unowned shafts,
  invalid targets and paths over128 cells. Physical contracts, route-aware travel,
  excavation/fill/restoration and owned verification receipt integration remain next.

- Native two-region water trial204/205 passed: nine verified glass and57 independently
  checked air cells, all32 temporary cobblestone returned, empty private chests, no
  active jobs/supply, worker idle at home with10676/12000 fuel. Both computers stopped,
  all six tickets removed and pause-on-focus-loss restored. Details are appended to
  [fluid acceptance](validation-fluid-preparation.md). The delayed-source retry path
  remains simulation evidence; this native run did not exhaust its initial retries.

- Access worker execution now passes87 focused geometry/preparation/construction,
  logistics and protection cases. Contracts require a contiguous owned route and
  matching work cells; existing dig/place journals open a shaft/tunnel, fill/verify
  hidden support and restore ground without disturbing a protected retained floor.
  Physical dig/place reboot cases preserve exact two digs/three placements and stock.
  Shared travel exits/reenters the recorded shaft and resumes a pending return step.
  Fuel admission includes the detour. `siteAccessV1` prevents older workers receiving
  access tasks, and duplicate assignments cannot change/remove the owned route.
  Controller access orchestration and final proof/restoration accounting remain to
  implement; no normal build currently creates these access tasks automatically.

- The stabilization snapshot passed all725 Lua tests (before the latest access
  receipt/controller edits);18 Python tests passed. Current-tree validation remains
  pending. Controller access now passes service checks for opening, filling, hidden
  support verification and reverse ground restoration across controller recreation.
  Only observed solid ground below planned clearance is restored. Original access
  receipts remain in the root until restoration commits to both region checkpoints;
  loss of both region files reconstructs restoration before fresh preparation.
  Three failed restoration attempts retain the region and an actionable error.
  A full controller/worker retained-floor runtime is running; no native automatic
  missing-support acceptance is claimed yet.

- The actual retained3×3-floor runtime found an exit-target bug: the target was
  recomputed from each intermediate tunnel position while a reserved route remained
  pending. The fixed shaft entrance is now used for the whole exit. Its focused
  reservation-yield regression and actual controller/worker reboot case pass, with
  every original floor/ground cell retained or restored and exactly one net fill.
- Interior regions now obtain bounded access through the project margin when no
  internal shaft exists. A durable project access lease spans child jobs and debris
  settlement, drains pre-existing owners, and withholds affected neighboring region
  certificates until restoration completes. Geometry/service checks and an actual
  nine-region retained-floor runtime pass. One access operation per project is the
  deliberate concurrency limit; unrelated regions remain usable.
- A new protection regression reproduced permission to mutate directly above/below
  another worker. Mutation grants now reserve the two vertical neighboring cells
  atomically and reject occupied/offline worker positions there. Both grant orders
  pass, along with the focused preparation/construction/protection tests. Fresh full
  current-tree validation is running. Native206/207 automatic access is running on
  the preceding within-region snapshot; it is not evidence for the later lease/guard.

- Foundation access implementation committed at`282b9dc`. The earlier access
  snapshot passed735 Lua tests (before cross-region access/vertical-guard changes);
  the newer ownership snapshot remains running. Current Python suite18/18 passes.
  Native206/207 has opened/restored multiple shafts and recovered a controller
  reboot during debris return; final acceptance is still pending.
- External-inflow containment now has failing-then-passing geometry/controller
  checks: bounded stable-fill perimeter outside required working air, fill/verify
  receipts, protected-cell defects, failed-checkpoint recovery and a fresh regional
  census only after verified containment. A new survey cannot abandon active wall
  work, and later survey generations preserve the physical barrier's protection.
- The actual inflow runtime reached a complete wall but exposed a simulator error:
  the fixture treated water/lava as solid movement obstacles. CC:Tweaked1.120.0
  TurtleMoveCommand and WorldUtil explicitly allow liquid movement. The fixture
  regression failed before correction and passes afterward; solid collisions remain.
  The complete inflow runtime is rerunning. Native containment remains pending.

- The access/ownership snapshot at`282b9dc` passed739 Lua tests, including
  cross-region runtime and atomic vertical worker guards. The newer containment
  snapshot is running;18 Python tests and release/diff checks pass.
- The corrected actual inflow runtime passes: an external source remains present,
  the outer barrier verifies, fresh preparation drains working air, and the glass
  target builds/verifies after both runtimes reboot. Barrier fill is restricted to
  known nonflammable materials and verified by exact name, so existing flammable
  generic support cannot certify a lava barrier.
- A settlement regression reproduced `built` between barrier batches. Settlement
  and retirement now share a pending-preparation/access check; the regression
  failed before the fix and passes afterward. Updated this controller-only module
  on206/208/210 and rebooted them without changing physical job contracts.
- Native trials now running independently:206/207 within-region hidden support,
  208/209 cross-region hidden support,210/211 external inflow containment. The first
  trial recovered an earlier controller reboot and a worker reboot at a confirmed
  shaft entrance between child jobs, with project pause/resume. No final native
  acceptance is claimed yet. Four loaded chunks per fixture; no world backups.
- Native206/207 automatic hidden-foundation acceptance passed:9 retained floor
  blocks verified,100 independently checked world coordinates, one net cobblestone
  consumed, restored ground, empty private inventories and idle worker at home.
  Both computers are shut down and their four force-load tickets removed. See
  [foundation access acceptance](validation-foundation-access.md).
- The single final0.23 review found three reproducible bugs: queued unowned builds
  deadlocked an access lease; a valid unfinished backup could strand a completed
  preparation root; and mining-only workers could neither request nor accept new
  mutation grants. The consolidated fix pass drains actual owners while fencing
  new overlapping admission, promotes terminal sidecar evidence and recovers older
  unfinished backups, and applies task-specific mining enablement to grants.
- The mining-only restart regression also exposed a saved granted reservation
  waiting forever for an unconstructed miner executor. Resume now runs after the
  mining service restores its engine and validates the saved configuration.
  Focused mining/service/protection tests pass, including restart, current backup
  promotion, older backup recovery and an admission lease acquired during a
  yielding chunk check. Full final validation remains pending. Controller-only
  preparation/admission fixes were deployed to208/210 and both restarted while
  their independent native trials continued.
- Native208/209 cross-region foundation access passed:all nine preparation regions
  completed,38 sampled child jobs crossed region boundaries,9 retained floor blocks
  verified,100 independent world checks passed, and net fill consumption was one
  cobblestone. All120 jobs completed; no access/supply lease remained. The worker
  returned home idle with12,470 finite fuel and empty cargo/private inventories.
  Both computers are off and their four test chunks released. The permanent
  [foundation report](validation-foundation-access.md#cross-region-access) includes
  deployment/restart evidence and limits. External-inflow acceptance remains active.
- The pre-review containment snapshot completed744 Lua tests successfully. The
  final committed review-fix tree has18 Python tests and release checks passing;
  its complete Lua run is still in progress. Do not confuse the earlier snapshot
  result with the pending final gate.
- Final0.23 code gate at`01d65e2` completed748 Lua tests and18 Python tests; release
  artifact and whitespace checks passed. Only later acceptance documentation changed
  in the main checkout. Native external inflow exhausted its initial and secondary
  retry budgets and began the retaining wall. The first eight-cell wall batch
  completed; a controller restart was queued during the next batch to test durable
  containment progress. Wall verification and final independent observations remain
  pending. The passive monitor was restarted after its one-hour sampling limit;
  explicit barrier-start and restart snapshots supplement the sampling gap.

- Native210/211 external-inflow acceptance passed:32 exact cobblestone wall blocks,
  one glass and17 air workspace cells,63 unchanged floor blocks and a retained outside
  source passed114 independent checks. All164 jobs completed; the worker was home,
  idle and empty with9,482 finite fuel. Central stock retained32 cobblestone and both
  private inventories were empty. Controller restart during wall placement preserved
  progress. The test computers are shut down and four test chunks released. Permanent
  [inflow](validation-external-inflow.md) and [0.23](validation-0.23.0.md) reports record
  fixture assumptions, sampling limits, full final gates and the single review pass.


## Current acceptance notes

-0.24's previous full gate exposed a chest encountered inside a traffic detour.
  The shared navigation fix persists only inspected physical obstacles, replans
  within the existing bounded route and never digs the chest. Deterministic reboot
  and opposing-worker regressions pass. All dependent final suites include it.
-0.27 review found early supply could exceed inventory capacity and strand staging.
  Native stack-space limits and conservative empty-slot capacity now bound demand;
  the actual runtime regression passes with64- and16-item stacks, partial receipt
  power loss,65 placements and exactly64 supplied items.
-0.27 review also found harvested progress was mistaken for deposited output.
  Task-bound measured delivery plus fresh cargo now keeps held and expected output
  disjoint. Actual HARVEST/FARM partial delivery and reboot regressions pass.
-0.28 retains explicit `build prepare`/`build start` full-stock behavior and owned
  legacy requests. New `build auto` runs use existing finite supply journals, so
  placing workers can overlap later mining/processing without a second ledger.
- Full implementation remains incomplete. Next work continues through software and
  equipment negotiation, processor/provider coverage, placement adapters, inventory
  rescue, scheduling and fleet monitoring, plus larger integrated acceptance.


- Review correction: the0.28 overlap test passed, but its cumulative-placement
  assertion did not prove a placement event concurrent with production. That
  concurrency claim is withdrawn pending stronger event-timed evidence. Final
  review also reproduced streaming supply acquisition continuing after project
  pause and a stale stockOnly flag disabling new-run acquisition. These remain
  release blockers for the consolidated regression-backed correction pass.
- Isolated next branch`milestone/0.24.0` at`.worktrees/fleet-scaling` starts
  requirement44 while0.23 final gates run in the main checkout. Its demand model
  validates limits for all five roles, computes active/idle/queue/work/rate views,
  accounts for travel and zero-yield searches, and records bounded physical-delivery
  samples with atomic rollback and restart deduplication. Seven new focused
  regressions and existing mining/coordination checks pass. Dispatch integration,
  diagnostics, actual-runtime/native acceptance and final review are still pending;
  no claim that scaling is active yet.

- Dynamic allocation now gates mining and workflow dispatch, splits exploration
  quotas among admitted workers, prefers specialized candidates and rechecks limits
  after yielding chunk calls. Ownership timestamps share the assignment checkpoint;
  failed writes restore the job and loaded-area lease. Existing owners remain valid
  after a reduced cap. Private crafting and hauling check limits before staging
  stock and drain existing claims even when the corresponding maximum becomes zero.
  Producer windows expand above their four-region lookahead floor for larger fleets.
- Focused0.24 ownership coverage passed110 checks; producer/service coverage passed60,
  and quota/crafting/hauling runtime coverage passed79. Regressions cover zero-cap
  staging, cap reduction during collection, stationary unfueled crafters, haul travel
  estimates and counting physical collection in delivery rates. Historical parallel
  recovery fixtures explicitly request two crafting workers (and the small shared
  mining accounting case two miners) to retain their original fault/concurrency
  coverage under the new automatic small-work policy. General bottleneck allocation,
  status/limit commands and native ramp/drain acceptance remain unfinished.

- Dynamic allocation now prioritizes actually dispatchable competing roles, prefers
  specialist explorers, accounts for unexpanded project/preparation backlog and
  exposes durable `fleet status`/`fleet limit` commands. Existing ownership, staging,
  quota-yield, runtime and exploration focused checks pass. A real-runtime miner
  scenario registered a second explorer after an empty trip, automatically shared
  eight cobblestone demand, survived controller restart and drained both owners.
- The larger four-worker construction scenario exposed an incomplete detour after a
  failed path search. A focused regression reproduced the nil-path exception; failed
  replanning now discards the incomplete route durably and retries under normal
  reservation checks after traffic clears. Another regression corrected private
  crafting rates to use collected output and factory start/completion timestamps.
  Both focused regressions pass; the larger construction rerun is still pending.

- Native0.24 fixture212–218 is running a48-block mixed cobblestone/glass project on
  uneven terrain. Only builder213 and miner217 began powered on; after each owned
  automatic work, builders214–216 and miner218 joined through ordinary registration.
  Two miners and multiple surveyors became active without assignment commands.
  Initial stock contains16 glass, no cobblestone; placed stone deposits supply the
  missing structure/foundation material. Six workers each started with20,000 finite
  fuel. The operator explicitly loaded18 chunks and supplied separate private endpoints.
- Native survey observations exposed underutilization from one queued neighboring
  region per worker. A regression admitted only two of four useful builders; exposing
  two candidates per worker (still bounded4..64) admits four separated regions while
  retaining every existing conflict check. Scaling/site/coordination tests pass.
  The long construction rerun was superseded by this producer-window change and is
  now running with periodic diagnostic snapshots; its earlier interrupted run is
  not passing evidence. Initial Python gate passed all18 tests.

- Private crafting now estimates the whole current production operation beyond its
  bounded queued batches, subtracting collected current-generation output. A focused
  test reproduced severe undercounting; a128-brick actual-runtime request now uses
  both private stations with default zero minimum, collects exactly128 output,
  releases capacity and drains allocation to zero. Scaling and factory runtime
  focused checks pass. This extends the same backlog treatment already used for
  bounded construction/preparation queues.

- The single final0.24 review found two reproducible Important issues. An unsupported
  first acquisition exited the whole exploration pass, starving later compatible
  demand. It now stops globally only when role capacity is exhausted; unsupported
  and offline-only material groups no longer block other miners. A pause arriving
  during native logistics capacity observations also permitted a new claim and
  transfer. Final eligibility now rejects paused/retired work; rollback snapshots
  begin after yielding observations so they preserve the newer pause. Regressions
  failed before fixes and pass afterward, including resumption after other hauling
  settles. No second review is planned.
- The initial full suite exposed an older coverage-status fixture that expected a
  second tiny build to dispatch beside an existing owner. It now explicitly requests
  minimum two builders so it still exercises missing chunk coverage. Production
  allocation remains unchanged. That preliminary suite was superseded by the review
  fixes and fixture correction; it is not final passing evidence.
- Native0.24 home returns correctly refused missing coverage for chunk64,-1 at the
  central storage boundary. The operator added two loaded chunks and widened only
  the controller's explicit assurance rectangle (now20 chunks), then restarted it.
  All three pending debris returns completed; preparation and building continued
  concurrently. This was fixture configuration, without extra stock or terrain edits.

- The48-block four-worker simulation completed placement but stalled at43 verified
  cells because idle workers remained at inspection destinations. The nil-path fix
  prevented a crash but could not move an occupied goal. A focused actual-runtime
  regression reproduced the stall. Denied movement now identifies the physical
  blocker and requests an ordinary managed home return only for an online, idle,
  unowned, capable worker away from its depot at that exact destination. Offline,
  busy, paused and already-home workers retain their protections. One physical
  regression and36 runtime/coordination/logistics checks pass; the large run is
  restarting. Preliminary full-suite runs were terminated after this new finding
  and cannot serve as final acceptance. No extra review pass was requested.

- Prepared the next dependency-following milestone for requirement10, persistent mining
  intelligence, in isolated `.worktrees/mining-intelligence` (`milestone/0.25.0`).
  The design reuses bounded exploration records and physical journals for inspection
  evidence, hazards, route history, density/yield ranking and explicit safe sector
  retries. Tasks50–52 record implementation and native acceptance. No0.25 implementation
  or acceptance is claimed yet;0.24 scaling native/final validation remains active.

- Task50 implementation now retains at most64 physical evidence cells per trip/sector,
  optional on the existing protocol for older workers. Inspection and scanner sightings
  persist alongside liquids, protected/failed digs and clear movement reconciled through
  the existing journal. Reservation denial never becomes geological evidence. Focused
  tests cover waterlogged blocks, movement recovery, sparse/oversized/out-of-contract
  evidence and retained ore sightings after excavation.
- A failing checkpoint regression exposed premature in-memory completion of exploration
  trips. Progress now rolls back the trip, sector history and acquisition together on
  failed save. Material-specific actual yield, successful/empty/inaccessible trip counts
  survive reboot and ignore duplicate terminal reports. Exploration, miner and mining
  runtime focused suites pass; this is implementation evidence, not0.25 acceptance.

- Task51 now ranks candidate sectors by retained material density, average physical
  yield and hazard count before distance ties. Route planning avoids retained negative
  cells and prefers confirmed clear direct steps while preserving current protection,
  leases, fuel and bounded search. Sector diagnostics expose coordinates and outcome
  counts; explicit retry preserves delivery history and refuses active/offline ownership.
  Retry checkpoint failures restore prior coverage and evidence.
- Both scanner and inspection-only actual-runtime autonomous-chain scenarios pass with
  controller/worker restarts. Their sector delivery totals equal independently simulated
  physical deposits; confirmed travel and resource sightings survive the restarts.
  The separate native219/220 learning fixture is running with2,000 finite fuel, a staged
  protected obstacle, empty first sector and six stone blocks beyond it. Eight chunks
  are explicitly loaded. Native acceptance and final review/gates remain pending.
- The larger scaling rerun exposed a separate movement stall: a traffic detour could
  enter another worker's reserved preparation volume, but that denial did not resume
  route planning. The worker now recognizes active preparation ownership as a traffic
  obstacle. A focused actual-runtime regression fails before the fix and passes after,
  verifying the protected volume remains unentered and its owner unchanged. Runtime,
  navigation and coordination checks pass. The48-block rerun continues; the same fix
  is installed on native workers213–216 with checkpointed tasks retained.

- The next larger rerun revealed symmetric traffic detours: opposing workers repeatedly
  chose the same passing lane, accumulated16 blocked cells and eventually hit terrain
  or stayed at the detour limit. A two-worker actual-runtime regression reproduces
  inaccessible verification after this synchronized movement. Navigation now tries a
  right-side step before its bounded onward search, separating approaching workers.
  Both workers verify successfully with all physical collision assertions enabled.
  A full obstacle cache is checkpointed away to permit later traffic changes; it no
  longer creates an absorbing blocked state. Focused navigation/runtime/coordination
  checks pass. Native workers213–218 received the fix; larger and final suites restart.

- The48-block four-worker runtime simulation now passes: late registration increases
  preparation/build ownership, a controller restart preserves work, all48 blocks verify,
  and all workers finish idle with empty cargo and positive finite fuel. The native run
  separately hit CraftOS's non-yielding execution limit during a checkpoint while
  handling network traffic. A native139,791-byte checksum benchmark took roughly15ms
  after warmup; moving yields into checksum transactions was unnecessary and unsafe.
  The event loop now drains at most8 packets or250ms per turn, between complete handlers,
  with a short follow-up timer while backlog remains. A burst regression fails before
  the change and passes after, preserving all21 packets in order. Runtime/navigation
  checks pass. Controller212 was restarted from its saved files with this fix; no
  worker ownership or cargo was reset. Final full-suite evidence will use this source.

- The single final0.25 review found three reproducible Important learning errors:
  inspected turtles became permanent hazards, long returns evicted discovered hazards,
  and preloaded depot cargo falsely credited unvisited sectors. Consolidated fixes now
  keep physical turtles on the transient reservation/retry path, retain unresolved
  negative evidence ahead of clear travel, and journal initial cargo separately from
  attributed mined yield. Total acquisition receipts remain unchanged; old reports
  conservatively add no mined yield. Regressions cover both scanner/inspection paths,
  a70-cell hazardous trip and its next route, initial-unload recovery, malformed/regressing
  counters and legacy reports. Focused exploration/miner/runtime tests pass. No second
  review is planned. Final native regression extension and complete gates remain pending.

- Native0.25 final-source review extension passed: preloaded depot cargo was excluded
  from mined yield; an actual turtle obstruction retained its active trip across a
  controller restart, then resumed automatically when removed. Independent reads
  confirmed nine stored cobblestone (eight mined plus one explicit preload), empty
  home cargo and1,846 finite fuel. Both computers are off and their eight test chunks
  are unloaded. See validation-0.25.0.md. Complete Lua gates remain running.

- Started0.26 mission fuel planning in isolated `.worktrees/fuel-forecast`, based on
  the0.25 native-evidence commit. The existing fuel-focused baseline passes. Design
  and Tasks53–55 extend shared bounded-excursion budgets, validated telemetry,
  proactive station targets and final dispatch admission. No0.26 implementation
  is claimed yet.0.24 native and0.24/0.25 complete Lua gates continue independently.

- Task53 shared role budgets and optional task-bound telemetry are implemented.
  Construction retains its original maximum excursion arithmetic; transport, rescue,
  home/station, farms, access work and bounded mining expose separate outward/work/
  return/reserve components. Unknown geometry remains explicit. Focused arithmetic,
  network, construction, fuel-service and automation runtime checks pass. The focused
  construction supply/fuel runtime regression is running before the task commit.

- Task54 now matches distinct queued missions to compatible idle workers, rechecks
  concrete fuel budgets at final admission and raises managed station targets before
  assignment. Red/green tests cover above-low shortage, native-limit refusal and a
  full-tank repeated-refuel bug; queue tests cover a fuel change during coverage
  observation and selecting a different ready worker. Role/network/coordination/
  coverage checks pass. An actual-runtime distant verification refueled first,
  survived controller reboot, completed correctly and conserved all four initial
  coal items with one consumed. Broader fuel runtime checks are running.

- The single final0.26 review found four Important forecast stalls: fixed miners lacked
  advertised entry geometry, undersized native tanks masked capable alternatives,
  non-dispatchable factory jobs masked ready movement, and exploration demand was
  invisible before a funded trip could exist. Each reproduces red and now passes
  with validated worker entry, tank-aware matching, existing readiness checks and
  bounded planner fuel-refusal estimates. No second review will run.
- Native0.26 confirmed100 fuel above low80 proactively increased to180 for a174-fuel
  verification, with one correct block. Final home return then hit the station chest.
  The actual-runtime extension failed the same way. Shared depot travel now reuses
  the station side approach; empty and mixed-cargo reboot regressions pass without
  digging or losing cargo. Final native recovery and complete gates remain pending.
- Final review rulings: whole-project unknown-terrain optimization remains outside
  the explicit bounded-excursion forecast; navigation still enforces actual reserves.
  Full suites and native acceptance remain mandatory parent gates. Neither declined
  item is treated as finished, and no external blocker exists.

- A final mining departure check exposed a worker/controller target mismatch:
  the worker could demand1,000 fuel after an apparently affordable assignment.
  Validated telemetry now carries its departure target even for idle explorers;
  initial and prospective budgets include it while active trips retain remaining
  work budgets. Arithmetic, telemetry and prospective-demand regressions pass.
  The superseded0.26 full run was stopped before restarting on this final source.

- Native0.26 clean retest passed across controller restart: proactive refuel before
  the174-fuel mission, one correct verified stone, automatic station-side home
  return, empty cargo and114 finite fuel. Independent reads reconcile8 initial
  coal as6 stored plus2 consumed. Final mining-target source rebooted idle.
  Permanent evidence: validation-0.26.0.md; complete Lua gate remains running.

- Started0.27 design in isolated `.worktrees/supply-forecast`: per-project material
  categories, retained measured material progress and bounded early builder demand.
  Ruling: implement these prerequisites before changing initial full-project
  preparation into overlapping production/construction; reusing current finite
  requests preserves ownership. Cost: the full continuous pipeline remains open.
  No0.27 implementation or acceptance is claimed yet.

- Task56 implementation now retains bounded correct-material totals through report
  compaction and retired task payloads, validates quantities against owned blocks,
  and exposes `build forecast`. Read-only forecasts allocate shared available stock
  once and distinguish provider estimates, reservations, transit and worker cargo.
  Red/green regressions cover mixed blocks, air/door halves, malformed/regressing
  totals, duplicate project demand, offline evidence and side-effect-free commands.
  The broader project runtime regression is still running; Task56 is not complete.

- Task57's early top-up now passes an actual-runtime red/green regression: a
  builder with one held stone requests its next item before placing the last,
  restarts both runtimes, places exactly two and reconciles one supplied item.
  Ruling: reuse the existing supply journal immediately at a safe action boundary;
  a second staging request would conflict with factory exclusion. Cost: the worker
  waits during replenishment. No new protocol or independent ownership was added.

- The full early-replenishment chain exposed stock consumption before its own
  acquisition group settled: one missing cobblestone caused two deliveries.
  Regression failed with two deposited/one pulled. A supply batch now waits for
  its linked finite production request to complete before first staging, while
  already-offered batches still drain. The actual controller/explorer/builder
  regression passes across both runtime restarts with exactly one mined, one
  supplied and two placed (including one initial held item).
- The prior supply-receipt timing test now expects the next batch before placement,
  retaining its assertion that an older receipt survives until acknowledgement.
  Full logistics runtime checks pass before the acquisition-settlement correction;
  final focused/regression checks and the complete release suite will include it.
- Forecast view retirement also has a red/green regression: deleting the selected
  project displays an empty selection instead of throwing from the next tick.
- Final0.25 clean-source gate completed:802 Lua tests,18 Python tests, release
  verification and whitespace checks pass. Native acceptance is complete.
  Integration remains ordered behind the still-running0.24 native scaling trial.
- Final0.24 full gate failed1/786 tests: the48-block ramp/drain fixture stalled at
 46 blocks. Retained state identified builder14 blocked by a chest encountered
  inside a traffic detour. The earlier focused pass did not exercise that ordering.
  A deterministic regression reproduced a terminal physical-obstruction error.
  Navigation now persists the inspected cell as bounded detour evidence and retries
  without digging. The regression passes across reboot; an actual two-worker
  runtime with opposing routes and station chests also passes. This is a release
  blocker corrected before restarting the full gate, not a waived flaky test.

- Propagated0.24 physical-detour correction after the earlier802-test pass. The
  complete0.25 gate is restarting on the merged source before integration.

- Propagated the shared physical-detour correction into0.26. Superseded the
  incomplete final Lua run and restarted on the merged source before integration.

- Task56 broader project runtime suite passed. The single final0.27 review found
  two important issues: oversized early top-up could strand staging, and harvesting
  progress was incorrectly treated as delivery. Focused red/green tests now cover
  native stack limits, full/reserved/tagged slots, validated delivery telemetry, and
  actual HARVEST/FARM collection, partial deposit and reboot. The larger capacity
  runtime regression and final release gates remain in progress.

- The full-cargo early-supply regression passes for64- and16-item stacks across
  power loss after a partial pull:65 placements,64 supplied items, empty staging
  and released ownership. Python18 tests, generated release verification and
  whitespace checks pass. Complete Lua and native acceptance are next.

- Started0.28 design in `.worktrees/continuous-pipeline`: automatic builds will use
  verified site regions and existing finite builder supply requests instead of
  waiting for a full-schematic stock target. Explicit prepare/start remains.
  Ruling: bounded supply journals already provide ownership and restart semantics;
  a second project-consumption ledger is unnecessary for fleet-wide overlap.
  Cost: each builder still waits during its own top-up; other builders/providers
  supply concurrency. Implementation and acceptance remain pending.

- Task59 empty-stock automatic run regression passes across pause/restart: verified
  site regions ask for bounded supplies without a whole-project stock request.
  Explicit preparation and saved legacy requests preserve their existing ownership.
- Task60 actual-runtime overlap regression passes: two builders place while later
  production remains active, then survive controller/builder restarts. Real miner,
  furnace, crafter and builder modules reconcile4 cobblestone,1 sand,4 smelted stone,
  1 glass,4 crafted bricks,3 placements and2 surplus bricks. Both builders return
  empty with finite fuel; requests complete and staging/ownership drain.
  Full regressions, native acceptance and final review remain pending.


- Review correction: the0.28 overlap test passed, but its cumulative-placement
  assertion did not prove a placement event concurrent with production. That
  concurrency claim is withdrawn pending stronger event-timed evidence. Final
  review also reproduced streaming supply acquisition continuing after project
  pause and a stale stockOnly flag disabling new-run acquisition. These remain
  release blockers for the consolidated regression-backed correction pass.

- Consolidated0.28 review correction passes targeted regressions: queued supply
  pause and active exploration pause survive restart without new acquisition;
  resume keeps request identities. A fresh ordinary run clears stale stockOnly,
  while active stock-only ownership remains. Shorthand idempotence reflects zero
  upfront project requests. An inherited first-site checkpoint interruption also
  has a red/green recovery fix through completed construction.
- Corrected overlap evidence now passes at the actual placement call while another
  miner is away on an active acquisition. Independent regions are separated beyond
  traffic exclusion and physically prepared first; adjacent regions correctly
  serialize. Controller/builders restart after that event;7 positions verify
  (3 material blocks plus4 required air), with exact material counts and idle drain.
  This replaces the withdrawn cumulative-placement claim. No second review is
  planned; complete release gates and native acceptance remain.

- Started0.29 health prerequisite design in `.worktrees/fleet-onboarding`: read-only
  equipment/peripheral evidence, managed installation integrity, bounded registration
  and new-work eligibility. Existing configured roles remain opt-in; owned work is
  retained. Source-copy fixtures must report unmanaged, not verified. The subsequent
  single-command onboarding flow remains required and is not declared complete.

- Task61/62 health implementation passes focused hardware/software/network/runtime
  and dispatch tests. Health is checked again after yielding coverage admission;
  existing owners retain assignments despite later damage. A legacy coordination
  fixture lacked the digging API its advertised mining role requires; its stub now
  explicitly exposes that API without permitting physical test effects.
- Native235/236 read-only checks report advanced pickaxe and normal crafting-table
  turtles correctly. Both retain777 fuel. A test-generated managed receipt verifies,
  detects an intentionally edited file, and verifies after restoration; source-copy
  software reports unmanaged. This is integrity/hardware evidence, not installer
  workflow acceptance. Final review, complete gates and integration remain.

- Started0.30 single-command enrollment design while0.29 final review runs. Reuse
  the installer transaction and validated setup persistence. A controller-provided
  worker ID/GPS berth profile supplies real station/pose configuration; discovery
  cannot invent a heading or infrastructure. Unknown profiles retain telemetry
  without enabling physical work. Implementation and acceptance remain pending.
- The single final0.29 review identified four important integration bugs and one
  hardware-reporting issue. Consolidated red/green regressions cover unhealthy
  courier/private-crafter selection before staging, health changes during capacity
  observations, impossible competing mining roles, repair digging requirements,
  incomplete manifest/receipt agreement and redirected terminal color. New stock
  claims now check health before ownership; owned journals still drain unchanged.
  Installer required-file invariants are shared with integrity verification.
- Focused health/network/runtime/coordination/logistics/scaling/install checks and
  actual private-crafting regression pass. Complete0.29 gates are starting; native
  integrity checks will be repeated on the final correction. No second review.

- Task63 discovery/profile tests pass: nonce-bound bounded replies, explicit
  controller selection, ambiguity refusal, ID/GPS berth matching, unmatched
  telemetry-only enrollment and forbidden profile fields. Runtime supports the
  opt-in enrollment protocol without requiring prior worker registration.
- Task64 initial flow reuses the existing transactional installer and extracted
  setup idle checks. Fresh enrollment applies a profile; repeats preserve settings;
  explicit refresh preserves known saved heading. Active jobs block before HTTP,
  failed profile application remains resumable, and release mismatch cannot enable
  roles. Focused tests and18 Python packaging tests pass. Native HTTP enrollment,
  final review and complete gates remain pending.
- Final-source0.29 native health retest passed on `c482afa`, retaining777 fuel
  on both turtles and correct verified/modified/restored/unmanaged reports.
  Both computers are off and their force-load ticket removed. Python18 tests pass;
  the complete Lua gate continues. Single-command enrollment remains in progress.
- Native0.27 passed twice. First run observed positive-cargo early mining and2/2
  verified blocks; independent world/foundation/inventory checks passed. Second
  run rebooted controller225 and builder226 during the ungranted replacement
  request, then verified2/2 and returned both workers empty. Final finite fuel:
  builder536,miner1986. Four finite production requests completed. Final independent
  inspection/cleanup and complete Lua gate remain before integration; see
  validation-0.27.0.md and ignored dist/live-supply-forecast/.

- Native0.27 final22 independent checks passed; computers225–227 are shut down,
  ten fixture force-load tickets removed and evidence monitor stopped. No player
  movement or world backup. Complete Lua gate and ordered integration remain.
- Final0.25.0 complete Lua gate passed804 tests, with18 Python tests and
  release/whitespace checks. Log: /tmp/fleet-025-final-full-v2.log. Ordered integration
  waits for0.24 native worker settlement; no feature gate is waived.
- Native0.24's accelerated1s heartbeat/3s registration fixture saturated the
  controller inbox, with repeated dropped-message warnings and slow durable retries.
  Restored shipped defaults5s/15s on212–218 through checkpoint-preserving reboots.
  Source code/ownership/physical cargo were unchanged. Audit settings and logs are
  in dist/live-scaling/default-network-timing/. High-rate overload remains a known
  limitation for later large-fleet performance acceptance; do not claim it solved.

- Final0.24.0 complete Lua gate passed788 tests, with18 Python tests and
  release/whitespace checks. Log: /tmp/fleet-024-final-full-v5.log. Ordered integration
  waits for0.24 native worker settlement; no feature gate is waived.


-0.24 native acceptance complete: project built with48/48 correct; all six workers
  home/idle/empty, both requests/groups complete, no active supply/mining/leases.
  Independent reads confirm150 solid foundation cells and402 clear workspace cells.
 40 mined cobblestone =32 structure +4 foundation +4 stored surplus;8 cleared dirt
  stored. Finite fuel reconciles. Complete gates788 Lua/18 Python pass. Permanent
  report validation-0.24.0.md records fixes, default timing and overload limitation.
  Computers212–218 are shut down,20 force-load tickets removed, monitor stopped.

- Integrated accepted0.24 dynamic scaling on main. Source/test/release artifacts
  match the fully tested milestone; integration only reconciles progress documents.

- Accepted0.25 mining intelligence:804 Lua/18 Python, final review regressions,
  native hazard/yield/restart/initial-cargo checks and cleanup complete. Imported
  accepted0.24 evidence without changing tested implementation.

- Accepted0.26 mission fuel forecasts:829 Lua/18 Python, release/diff checks,
  single final review fixes, native above-low refuel/restart/home return and cleanup
  complete. Accepted0.24/0.25 documentation merged with tested source unchanged.

- Final0.27 gate passed846 Lua tests and18 Python tests, with release/diff checks.
  Accepted0.26 documentation merged without changing tested implementation files.
  Permanent0.27 report includes both completed native trials and confirmed cleanup.

- Native0.28 completed both runs. First empty-stock construction finished but did
  not capture overlap. The second consumed its two measured surplus bricks while
  acquiring new glass ingredients; brick placement overlapped an away sand miner,
  then controller/builders rebooted and all7 positions verified. All60 independent
  final world checks passed, all workers returned empty, three requests completed,
  and stock/supply/mining ownership drained. Seven computers shut down and twenty
  force-load tickets removed. Full Lua gate remains; permanent candidate report
  records the first-run limitation and stronger retest evidence separately.

- Final0.28 full gate passed853 Lua tests,18 Python tests and release/diff checks.
  Accepted0.27 documentation merged without changing the tested source. Both
  native trials, overlap/restart proof and cleanup are permanently documented.

- Started0.31 registered processing design while enrollment receives its final
  review. PROCESS operations will reuse dependency, reservation and physical
  transfer accounting for inventory-exposed machines, with explicit slot recipes,
  item fuel, capacity and processing-time estimates. Non-automatable hardware is
  reported unsupported. Implementation and acceptance remain pending.
-0.30 single final review found four Important issues; consolidated fixes preserve
  source-copy worker settings/checkpoints, separate software release discovery from
  enrollment GPS validation, reuse configuration object/collection merge semantics,
  and fail closed on incomplete unpinned discovery. All four new regressions failed
  before the changes and pass afterward; enrollment/setup/install/runtime focused
  suites pass. Full gates and final-source native repair retest follow.

-0.31 registered processors now have bounded recipe/machine schemas, PROCESS
  provider and dependency/fuel planning, balanced finite jobs, private machine
  claims, per-batch destination capacity, exact measured transfers and unused-fuel
  return. Initial regressions pass for concurrent multi-input machines, partial
  transfers, power-loss/paused reconciliation, unavailable power, changed owned
  recipes, release crashes, failed claims, disconnects and contamination. Native
  controller239 with two blast furnaces and a smoker is prepared; acceptance,
  final review and full gates remain pending.

- Started0.32 in isolated `.worktrees/renewable-providers`: extend the existing
  renewable actor through registered plant definitions, explicit planting reserves,
  seed-as-output accounting and health-aware acquisition choices. Processor0.31
  remains under its single final review/native acceptance; earlier gates continue.
-0.31 single final review and native trial found four Important issues plus uneven
  multi-wave lane balance. Regressions reproduced nominal-fuel exhaustion after
  streamed burn loss, obsolete acquisition dispatch after external supply, output
  capacity stranded across chests, and first-product stack-bound deadlock. Fixes
  reserve conservative per-batch fuel, retire only provably unowned unique demand,
  combine destination claims, support declared/measured output stack limits and
  balance machine quotas before finite splitting. Focused consolidated suites pass.
  The initial native run produced4 iron and2 cooked beef; the restart retest stalled
  at19/20 iron, independently confirming expired burn and one retained raw input.
  Fixture staging had removed the first4 ingots and was corrected with additional
  raw ingredients, never finished outputs. The stalled candidate is preserved in
  local audit records and its rig is reset for final-source acceptance.
-0.30 final-source native retest passed: real HTTP software repair preserved local
  settings and checkpoint bytes; partial profile refresh retained supply inventory,
  side and west heading, changed batch2→1 and consumed no fuel(1,188 unchanged).
  Worker registered idle with verified0.30.0 software. Computers237/238 shut down
  and all four temporary tickets removed with confirmed cleanup receipt. Permanent
  candidate report validation-0.30.0.md records automated/native evidence and limits;
  complete Lua gate is still running and acceptance is not yet claimed.
- Accepted0.29 worker health:868 Lua/18 Python tests, release/diff checks, single
  final review fixes and final-source native hardware/integrity checks complete.
  Accepted0.28 merged with tested implementation unchanged; ordered integration
  proceeds while enrollment and processor milestones continue independently.

-0.32 actual actor regressions now cover carrot seed-as-output surplus, beetroot
  maturity, interrupted replanting, immutable custom definitions, retained reserves,
  custom column bases, forecast exclusion and versioned worker eligibility. Focused
  registry/actor/fuel/forecast/provider/runtime suites pass; native controller241 and
  farmer242 are starting a two-plot carrot/replant/reserve acceptance run.

- Started0.33 placement-adapter design in isolated `.worktrees/placement-adapters`:
  extend existing classification/plans/journals for paired beds, attachments,
  deterministic rail/redstone states and simple plants, with explicit analyzer
  feature/tool diagnostics. Renewable0.32 remains in final review/native acceptance;
  enrollment/processor complete gates continue without source changes.

-0.33 implements bed pair journals/accounting/support order, finite attached and
  basic redstone/rail strategies, native seedling placement, final neighborhood
  verification and analyzer family/paired-footprint checks. Focused actor tests
  cover per-cell grants and restart, missing paired floors, protected cells,
  contradictory halves and powered-state rejection. Native probes confirm floor,
  wall and ceiling facings, both rail axes, bed orientation, wire connections,
  opposite repeater/comparator facing and farmland seed placement. Full project
  acceptance, single final review and release gates remain pending.
-0.32 single final review reproduced five issues: frozen adapters rejected by
  controller protection, same-identifier crop maturity skipped, unowned farm
  fallback stuck on the old capability contract, missing replant placement health
  admission, and pending planting cargo overstated in forecasts. Consolidated
  corrections preserve configured territory and durable adapters, reuse guarded
  acquisition retirement, check actual replant contracts, and carry one bounded
  planting obligation through telemetry. Regressions include real provider/queue
  mutation grants, overlapping owners, registry changes/reboots, retirement save
  failure and owned/offline/journal preservation. Native initial carrot task was
  blocked before any digging; its retained owner is resumed with these fixes.
-0.32 native acceptance then exposed a physical soil bug: descending into an
  empty crop cell for soil inspection converts farmland to dirt under the solid
  turtle. Crop replanting now relies on native seed-placement substrate validation
  from above; tree soil checks remain. A world-faithful regression fails before
  the fix and passes after, including rejected substrate, retained ownership and
  restart. The first native owner completed after operator restoration of the
  soil damaged by the old code; an untouched-plot final-source retest follows.
-0.32 final-source native untouched-plot retest passed after controller/worker
  restart: both crops replanted, both farmland blocks intact,7 carrots stored,
 2 retained planting carrots, farmer home/idle with1,942 fuel. Both requests/jobs
  completed, computers241/242 shut down and4 force-load tickets removed. Permanent
  candidate report validation-0.32.0.md distinguishes assisted pre-fix recovery
  from the clean retest; final complete Lua/Python gates are running.
-0.33 single final review found unsafe destructive bed repair plus six integration
  defects. Consolidated regressions/fixes refuse paired bed removal, remove ceiling
  support cycles, separate bed floors from pair regions, include generated cells in
  ownership/coverage, count one reactive supply item, preserve existing farmland
  through side inspection, and negotiate new placement capabilities. Ordinary crop
  project preparation/build/restart passes without trampling or replacing soil.
  The actual bed supply regression additionally exposed preflight cache invalidation
  before a mutation grant, which repeatedly discarded the grant through navigation.
  Invalidation now checkpoints with the placement intent; one stocked bed completes
  both halves after interrupted supply and controller/worker restart. Focused
  consolidated suites pass; native mixed-project retest and full gates follow.
