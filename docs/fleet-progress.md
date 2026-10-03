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
- Current branch: `milestone/0.19.0`; Task29 registered infrastructure nodes, then
  reserved physical logistics and automatic restocking.
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
| 1–2, 40, 43: complete fleet and hands-off pipeline | Small autonomous chain live-verified in 0.12.0 | Concurrent mixed-material large fleet, binary schematic entry, automatic recovery, safe final return |
| 3: coordination, persistence, physical accounting, capabilities | Existing queues, journals and validated worker telemetry | Extend the same guarantees to all new providers/reservations |
| 4: logical roles | Miners, builders, Crafty workers, furnace controller, managed farms and courier executor | More harvest/processor adapters, fleet-level logistics/rescue; optional scouting |
| 5: automatic registration | Installer, discovery/setup sharing, reconnect and capabilities | Single fleet install flow, equipment/software negotiation, automatic eligibility |
| 6: schematic analyzer | Native/desktop Sponge v2/v3 import, bounded gzip/NBT, transforms and supported-state classification | Supported block entities/fluids/redstone analysis, required tools and broader placement adapters |
| 7: recursive dependency graph | Aggregated nodes, shared stock/surplus, operation edges, bounded expansion; 417 Lua tests | Accepted 0.13.0; preserve during later integration |
| 8: provider registry | Deterministic candidates, availability/preferences, durable acquisition selection | Accepted 0.13.0; preserve during later integration |
| 9: autonomous mining | Accepted 0.12.0 with four live explorers | Preserve during later pipeline integration |
| 10: mining intelligence | Surveys, observed resources, protection, routes and exhaustion | Persist hazard/inaccessibility/density evidence and apply ranking |
| 11: fuel management | Configurable fuels, durable stations, automatic refuel and native rescue accepted; budgets deny unsafe trips | Per-mission budget presentation for every role and fleet-wide predictive fuel forecasting |
| 12: logistics network | Journaled point-to-point courier and supply batch executors | Pickup/destination capacity reservations, automatic station routing and dispatch |
| 13: storage abstraction | Durable count claims and physical/available/reserved/transit/expected/project views accepted in 0.14.0 | Native slot capacity and private station ownership accepted in0.16; general courier integration remains |
| 14: continuous forecasting | Acquisition targets and shortages | Proactive per-project coverage of all physical/expected states |
| 15: parallel crafting | Two native private Crafty stations with input/output leases, finite batches and restart acceptance | Automatic capacity-based batch sizing, cross-role pipeline integration |
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
| 38–39: completion and failures | Verified small projects and visible blocked states | Final inventory/logistics/worker settlement gate, bounded automatic retries and actionable project errors |
| 41–42: dependency-ordered milestones | Exploration, dependency/provider graph and count ownership integrated | Implement remaining milestones using existing controller/executor boundaries |
| 44: dynamic fleet scaling | Shared-material explorers and capability-based queues provide partial foundations | Demand/yield/travel/rate allocation, role minimum/maximum counts, bottleneck response, safe idle reassignment and scale-down; simulation and live miners/clearers/builders ramp-up |
| 45: automatic site preparation and leveling | Existing site-preparation executor and placement inspection provide partial foundations | Full footprint/workspace survey, intended multi-elevation foundations, excavation/fill acquisition, fluid/falling-block rechecks, durable independent regions, verified preparation gates, partial-structure preservation and uneven-terrain live acceptance |

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
