# Autonomous exploration implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans
> for native execution, or superpowers:subagent-driven-development if the user
> selects delegated execution. Steps use checkbox syntax for tracking.

**Goal:** Multiple turtles automatically discover and deliver materials for a small
schematic, then the existing factory and builder finish and verify it.

**Architecture:** Keep controller ownership, the existing mining transport and
physical executor, and capability-based dispatch. Add finite exploration trips
under provider-tagged acquisition groups; the controller chooses sectors and
accounts for outstanding quotas while workers report actual transfers.

**Tech stack:** Lua 5.2 compatible CC:Tweaked programs for the repository's Minecraft
Java 1.20.1 target; existing Python/Lupa tests and Python standard-library tooling.

**Spec:** [Milestone 1 design](autonomous-mining-design.md), governed by the user's
[full fleet requirements](fleet-requirements.md), especially sections 41 and 42.

**Execution:** Tasks 1–8 are implemented, integrated and released as `v0.12.0`
(commit `fc15407`). Final checks: 406 Lua tests, all 16 Python tests, release
and clean-tree checks passed. Live acceptance completed; see the permanent
[0.12.0 report](validation-0.12.0.md). Track all remaining requirements and
execution rulings in [fleet progress](fleet-progress.md).

The user authorized continuous native implementation, routine integration/pushes
and destructive Minecraft test-world changes on 2026-10-02. Proceed through the
remaining source-of-truth requirements without milestone approval pauses.
Tasks 1–8 constraints apply to the released exploration milestone; later tasks
explicitly extend them according to the full fleet requirements.

## Global constraints

- Sectors are 8 by 8 by 3, with at most 4096 sectors in an envelope.
- The proposed setup defaults are horizontal radius 64 and base Y minus 16 through
  base Y plus 16, clipped to dimension limits.
- The maximum requested-item quota is 64 per trip; keep at most 64 material
  observations per sector. Observations are not available inventory.
- Route length cannot exceed `maxTravelDistance`; retain existing fuel reserves.
- Exploration defaults off. Preserve saved fixed-box jobs, settings, the completed
  pilot and the current factory/storage exclusion behavior.
- Validate and save ownership before physical effects; never reassign an offline
  owner's territory. Never promote ambiguous recovery to successful completion.
- No new dependencies, second scheduler, speculative provider framework, runtime
  chunk-loading claim, or parallel-crafting implementation in this milestone.
- Later inventory reservations must permit the continuous pipeline required by the
  full fleet requirements. The current factory barrier is temporary.

## Review focus

1. Negative coordinates and envelope expansion must preserve sector identity and
   old survey progress. Pin this in task 1.
2. A returned item can enter stock before its report arrives. Outstanding demand
   must remain conservative without deadlock or duplicate credit. Pin in task 3.
3. Missing/cyclic/oversized route or observation data must fail before copying or
   mutating state. Mixed-version workers must keep functioning. Pin in task 2.
4. Falling gravel, waterlogged terrain, a full inventory, or a failed checkpoint
   around a dig must not cause unbounded digging or invented output. Pin in task 4.
5. Pausing, disabling exploration, or importing a conflicting project while a turtle
   is away must preserve a reconciled return and existing ownership. Pin in task 6.

## File responsibilities and data contracts

Add `autobuilder/resources/exploration.lua` for deterministic geometry, candidate
ordering, routes and bounded survey records. Keep hardware execution in
`resources/miner.lua`, job ownership in `core/jobs.lua`, and runtime/message
integration in `core/mining_service.lua`. Do not move legacy mining to a new queue.

Use `state.exploration = {schema=1, gridBase=position, sectors={}, groups={}}`.
Sector keys are integer grid coordinates relative to the saved base, independent
of current envelope size. A sector stores material-specific cursors/outcomes and
at most 64 observed material coordinates. Claims are derived from live trip jobs;
do not create a second authoritative ownership map.

An acquisition group has `id`, `key`, `provider='exploration'`, `item`, `target`,
`tripIds`, `paused`, `status` and `error`. Its target is a live-stock target, not a
sum of predicted drops. Only a physical job in `state.jobs` owns a worker.

A physical trip remains `type='MINE'`, with ordinary `id`, `item`, `quantity`,
`workerId`, `status` and `progress`. Its optional `exploration` record contains
`version=1`, `groupId`, `sectorId`, `bounds`, `entry`, `route`, `exitRoute`, `cursor`,
`envelope` and `protectedAreas`. The original payload is immutable after assignment;
mutable execution progress is saved separately on the worker. A completed legacy
MINE still requires its full assigned quantity; only a validated exploration trip
can complete with a partial delivery and terminal result.

New workers advertise `capabilities.explorationV1=true` only when configured for
exploration. Add a validated `explorationHome` telemetry record containing depot,
declared clear exit route and local protected boxes. The controller supplies the
current envelope on each new assignment; the worker checks it and its own local
restrictions before saving. Saved assignments are never widened by a later expansion.
Discovery observations
travel in bounded progress records, never unrestricted copied tables.

Terminal results are `quota`, `survey_exhausted`, `cargo`, `fuel`, `paused` and
`route_blocked`; all require arrival at the assigned depot and reconciled unloading.
`blocked` remains nonterminal when return or inventory state is uncertain.

## Development checks

Use the existing harness. Register each new Lua test file in `tests/run.lua`.
For each task, first run the new regression and establish the intended failure;
then implement and run it again. The normal verification command is:

```sh
.venv/bin/python tests/run.py
```

Success is exit 0, no `FAIL` lines and the final test count. Do not infer success
from intermediate output. Run the Python suite and release checks at task 8.
Use an isolated worktree at execution time, following the worktree skill.

### Task 1: Exploration configuration and deterministic geometry

**Files:** Create `autobuilder/resources/exploration.lua` and
`tests/exploration_test.lua`; modify `autobuilder/config.lua`, `tests/run.lua`.

**Interfaces:**
- `E.validate(explorationConfig) -> true | nil, reason` validates enabled geometry.
- `E.sectors(explorationConfig) -> sector[]` returns clipped boxes and stable IDs.
- `E.candidates(records, config, item, start) -> sector[]` orders known observations,
  then distance, then suggested-height difference, then x/y/z grid coordinates.
- `E.plan(sector, context) -> geometry | nil, reason`; context contains config,
  depot, exitRoute, protectedAreas, activeJobs, confirmedClear and availableFuel.

- [x] Add tests for disabled defaults, mode-specific required settings, negative
  coordinates, clipping, 4096-sector acceptance, 4097-sector rejection, stable IDs
  after expansion, deterministic ordering and route/protection conflicts. Expanding
  a previously clipped edge sector must expose its newly added cells for survey
  without discarding the old cursor or changing an already-owned trip's geometry.
- [x] Run the suite and confirm the new module/config contract is the failure.
- [x] Add `mining.mode='fixed'|'explore'` with fixed default and optional dense
  `mining.exitRoute`. Add exploration configuration with enabled=false by default;
  enabled configurations require base, envelope bounds, dimension bounds and base
  protection. Validate the explicit schema rather than allowing arbitrary keys.
- [x] Implement the geometry functions with existing `pathfinding.find`. A route
  consists of adjacent coordinates from the depot exit to the sector entry;
  depot exits are declared already-clear traversal only. Cap route entries at
  `min(floor(maxTravelDistance),1024)` for bounded messages. Reject a mission whose
  outward route and return cannot fit fuel plus reserve; work uses a live return
  threshold. Unlimited fuel still respects geometry and route length limits.
- [x] Verify tests pass; commit this independently testable geometry/config change.

### Task 2: Negotiated exploration assignments and reports

**Files:** Modify `autobuilder/workers/agent.lua`, `autobuilder/core/network.lua`,
`autobuilder/core/mining_messages.lua`, `autobuilder/config.lua`,
`tests/network_test.lua`, `tests/resources_test.lua`.

**Interfaces:** Existing `MiningMessages.validate(kind,p)` and `clean(kind,p)`
accept optional assignment `p.exploration` from the data contract. Progress adds
`p.exploration={result,cursor,observations,clearedRouteCount}`. Add `mine_return`
carrying only `jobId` to request a safe return. Existing envelopes remain version 1;
the new assignment payload is explicitly versioned and capability-gated.

- [x] Add round-trip tests for valid exploration telemetry/assignment/progress and
  rejection tests for sparse/cyclic routes, nonadjacent waypoints, false coordinates,
  out-of-envelope entries, excessive observations, unknown results and legacy
  packets acquiring exploration fields through unvalidated copying.
- [x] Run and observe the new protocol assertions fail.
- [x] Validate dense lists before copying; route cap is 1024, observation cap 64 per
  report, sector axes at most 8/3/8. Check finite integers, bounded strings and
  geometry membership. Copy only known validated fields. Preserve old telemetry
  and fixed mining messages byte-for-field where unchanged.
- [x] Advertise exploration support and home geometry from valid worker config;
  keep ordinary capabilities independent of role labels. Return unknown or
  malformed exploration data as an error, not an unrestricted legacy assignment.
- [x] Verify tests pass; commit protocol and capability negotiation.

### Task 3: Acquisition groups and finite trip ownership

**Files:** Modify `autobuilder/core/jobs.lua`, `autobuilder/resources/exploration.lua`;
create `tests/exploration_jobs_test.lua`; modify `tests/run.lua`.

**Interfaces:** Extend the existing jobs object with
`requestAcquisition(item,target,stock,key) -> group | nil,reason`,
`setAcquisitionPaused(groupId,paused) -> true | false,reason`, and
`refreshAcquisition(groupId,stock) -> group`.
Existing `assign(workers,counts)` returns legacy jobs or exploration physical jobs;
existing `progress(workerId,p,stock)` routes new trips by their saved group link.
`E.record(records,trip,report) -> true | nil,reason` merges validated observations
and survey cursors, preserving ownership in the job records.

- [x] Add tests where a demand of 128 and two capable workers produces two disjoint
  64-item trips. Assert unavailable/offline workers retain claims, zero/partial
  results leave the group open, duplicated reports do not alter credited counts,
  and failed saves produce no dispatchable ownership.
- [x] Add delayed-report cases: stock increases before progress, incidental drops
  satisfy another material, stock refresh fails, and a partial result arrives after
  a restart. Assert no new quota exceeds uncovered demand and conservative waiting
  ends after reconciliation. Also test duplicate request keys and legacy groups.
  Temporary route/sector ownership conflicts must produce waiting, not permanent
  inaccessibility or search-envelope exhaustion.
- [x] Run and confirm these tests fail for the missing acquisition behavior.
- [x] Implement quota allocation from refreshed stock minus outstanding undelivered
  quotas. Choose geometry using task 1 and require the task 2 capability. Persist
  the trip, group linkage and original quota atomically before returning a job.
  Respect the existing factory barrier and workerBusy checks across both queues.
- [x] Accept terminal partial results only for a saved exploration owner, retain
  transfer uncertainty, and complete a group only with enough stock and no owned
  physical trips left to reconcile. Exhausted or inaccessible candidates produce
  visible shortfalls. Revisit only an unfinished cursor or newly permitted sector.
- [x] Verify tests pass; commit acquisition accounting and assignment.

### Task 4: Physical exploration and journaled excavation

**Files:** Modify `autobuilder/resources/miner.lua`,
`autobuilder/resources/exploration.lua`, `tests/miner_test.lua`, `tests/world.lua`.

**Interfaces:** Preserve `Miner.new(task,hw,config,nav,inventory,scanner,save,clock)`.
For `task.exploration`, use saved assignment geometry and mutable
`task.explorationProgress={cursor,observations,clearedRouteCount,result}`.
Add executor `requestReturn() -> true | false,reason`; keep `step()` and `resume()`.

- [x] Add physical-world tests for excavation on the explicit access route, a
  partial survey followed by return, cursor persistence across unloading, full
  cargo, finite fuel, optional scanner and inspection-only operation. Assert
  unrelated cells and protected exits are never dug.
- [x] Inject failure immediately before/after dig, movement and deposit. Include
  falling gravel, waterlogged blocks, a changed tool slot, foreign item metadata,
  and an obstacle on return. Assert exact observed delivery or a preserved blocked
  intent; never repeated unbounded digs, spillover to slots 15/16 or false success.
- [x] Run and establish the failing physical regressions.
- [x] Limit dig permission to the assigned sector and access route. A clear exit
  permits traversal only. Reuse scanner and inspection fallback; survey each
  sector layer so a saved survey cursor describes the actual pattern attempted.
  Keep observed targets and confirmations bounded using task 3's record format.
- [x] Journal exploration digs using the existing site's before/after block and
  inventory approach, adapted to allowed mining drops. Unreconciled outcomes block.
  Require new inspection after each falling block and cap retries at the existing
  site-clearing bound of four; never infer a clear target from dig's return alone.
- [x] On trip end, retrace the saved trail, unload measured cargo and expose the
  terminal reason. Low fuel and full cargo are partial trip results after unloading;
  blocked return remains nonterminal. Fixed-box mining retains existing behavior.
- [x] Verify tests pass; commit the executor and recovery behavior.

### Task 5: Runtime dispatch and crash recovery

**Files:** Modify `autobuilder/core/mining_service.lua`,
`autobuilder/core/runtime.lua`, `autobuilder/core/receipts.lua` if receipt shape
requires it; extend `tests/mining_runtime_test.lua`, `tests/receipts_test.lua`.

**Interfaces:** Retain current service `tick`, `step`, `handle` entry points.
Send the task 2 fields from saved jobs; instantiate task 4 with the original
payload. Completed exploration receipts retain delivered count and terminal
survey result so acknowledgements can be retried without repeating physical work.

- [x] Add runtime tests for dropped assignments, dropped terminal reports/acks,
  duplicate dispatch with different geometry, controller/worker restarts during
  partial unloading, and backup recovery missing the original assignment.
- [x] Assert a changed local fixed mining box does not rewrite an exploration
  assignment, old receipts still replay correctly, and an offline owner cannot be
  replaced merely because its heartbeat expired. Run and observe failures.
- [x] Wire validated assignments and reports through existing transport. Worker
  duplicate acceptance compares the immutable exploration geometry too. Restore
  active saved exploration execution even if new exploration dispatch is disabled.
- [x] Extend safe receipt retirement to group/trip references and acknowledged
  survey state. Never delete a trip while production references it or worker
  telemetry still reports it. Keep bounded historical receipts and confirm backup
  recovery cannot recreate a lease from a worker's unsupported claim.
- [x] Verify tests pass; commit runtime/recovery integration.

### Task 6: Production, protection and pause integration

**Files:** Modify `autobuilder/core/production_service.lua`,
`autobuilder/core/workflows.lua`, `autobuilder/blueprint/projects.lua`,
`autobuilder/resources/exploration.lua`; extend `tests/coordination_test.lua`,
`tests/project_runtime_test.lua`, `tests/exploration_jobs_test.lua`.

**Interfaces:** Production keeps legacy `request.mines`; add
`request.acquisitions[item]=groupId` for provider-tagged exploration groups.
`E.protectedAreas(appState,config) -> box[]` derives project/depot protection and
combines it with explicit protected infrastructure. Project pause calls
`setAcquisitionPaused` and retries `mine_return` until owned workers return.

- [x] Add tests proving registered mining resources choose exploration when
  configured, farms still use HARVEST/FARM, recipes still use production operations,
  and no capable explorer yields an actionable blocked reason.
- [x] Add project-import overlap, paused outbound mission, disabled exploration,
  missing stock, and outstanding unload tests. Assert no factory starts before
  every affected physical miner has returned and reconciled. Run and observe failures.
- [x] Use the existing resource request -> acquisition -> physical-job boundary;
  tag the exploration provider without introducing a generic registry prematurely.
  Aggregate each group's workers and shortfall into the existing material status.
- [x] Build protected boxes from transformed imported volumes and known stations,
  including standing/overhead clearance used by current build routes. Treat the
  configured base protection and explicit infrastructure boxes as dig exclusions.
  Refuse project/config mutations conflicting with owned work before saving them;
  never authorize a protected-area dig to recover progress.
- [x] Preserve explicit cleared exit traversal without weakening the global
  navigation restrictions: the exploration route admits only its prevalidated
  clear-exit cells, and the dig guard still rejects them. Unknown return pose or a
  newly invalid route stops with a recovery explanation.
- [x] Verify tests pass; commit pipeline/protection/pause integration.

### Task 7: Operator setup, status and bounded expansion

**Files:** Modify `autobuilder/setup_wizard.lua`, `autobuilder/setup_share.lua`,
`autobuilder/core/mining_service.lua`, `autobuilder/ui/ui.lua`,
`tests/setup_test.lua`, `tests/mining_runtime_test.lua`; add
`docs/autonomous-mining.md` and update `docs/material-team.md`.

**Interfaces:** Add `setup exploration` on the controller and
`setup miner explore` on a worker, preserving resource-profile setup.
Controller commands: `exploration status`, `exploration expand <radius>`,
`exploration pause`, `exploration resume`.

- [x] Add setup transcript tests for valid save, cancel, missing depot/pose, bad
  exit routes, conflicting protection, invalid dimension bounds and active jobs.
  Add command tests for expansion that preserves IDs, shrink rejection, 4096-sector
  limit and keeping offline ownership. Run and observe failures.
- [x] Reuse setup's transactional settings save. Prompt for the base, operating
  boundary, loaded-area assumption, infrastructure protection and declared clear
  exits; display coordinates before saving. Do not move or consume fuel merely to
  detect hardware. Require known heading when it cannot be established.
- [x] Show material target/live stock, all owners, sector/cursor, trip quota,
  state/fuel and actionable shortfalls. Keep existing screens usable on small
  terminals. Log assignments, partial deliveries, exhaustion and recovery using
  the existing logger, without flooding normal screens.
- [x] Explain exactly how to place/connect deposit chests, provide startup fuel,
  configure exits, keep the envelope loaded, import the current JSON schematic
  format and run `build auto NAME`. Clearly label direct `.schem` commands and
  automatic fuel rescue as later requirements, not implemented commands.
- [x] Verify tests pass; commit setup, commands and operating documentation.

### Task 8: Full acquisition to verified construction and release checks

**Files:** Extend `tests/autonomous_chain_test.lua` and its local `fixture(options)`;
modify `README.md`, `docs/autonomous-mining.md`; add
`docs/validation-autonomous-mining.md`; regenerate `manifest.json` and
`installer.lua` with the existing release tool after source changes stabilize.

**Interfaces:** Extend the existing local fixture with
`options.exploration`, `options.scanner`, `options.finiteFuel` and
`options.restartAt`; retain existing defaults and existing tests.

- [x] Add a small-project test with two explorers sharing cobblestone demand, raw
  coal/sand discovered in other sectors, no configured deposits, and no preloaded
  finished building blocks. Assert distinct ownership, an empty first-sector result,
  real deliveries, furnace/crafting output, exact placement and clean verification.
- [x] Repeat with inspection fallback and finite fuel; inject controller/worker
  restarts plus lost terminal acknowledgements. Assert every worker is accounted
  for and no active exploration claim or unresolved transfer remains. Establish
  that the new acceptance tests initially fail on the missing integration.
- [x] Fix only demonstrated integration gaps; preserve the original autonomous
  chain and pilot tests. Record resource/fuel fixture setup so results do not imply
  fuel distribution or chunk-loading support that was not implemented.
- [x] Run `.venv/bin/python tests/run.py` and
  `python3 -m unittest discover -s tests -p 'test_*.py'`. Require successful exits
  and inspect any skips. Record new counts from output, not this plan.
- [x] Generate a 0.12.0 candidate with
  `python3 tools/release.py --version 0.12.0`, then run
  `python3 tools/release.py --check`, the installer tests in the Lua suite and
  `git diff --check`. Keep the existing release base URL; do not publish or update
  live computers as a side effect of generating artifacts.
- [x] Write the validation record and live checklist: loaded test area, two miners,
  one crafter, furnace/storage and one builder; second-sector selection, partial
  delivery, pause/return, reboot recovery and verified construction. Mark the live
  trial pending unless it actually ran in Minecraft. Commit the verified candidate.

## Continued execution: milestone 2, resource dependency graph

**Spec:** [resource dependency design](resource-dependency-design.md), fleet
requirements 7–8 and 41. Use native execution and test-first changes. Keep the
0.12.0 behavior as the regression baseline. Do not rewrite its physical queues.

**Review focus:** shared intermediate stock must not be spent twice; provider
preferences must not steal active ownership; sparse/unknown preference data must
fail validation; recipe expansion must remain bounded and reject invalid yields;
missing workers/providers must produce recoverable status, never phantom stock.

### Task 9: Resource provider registry

**Files:** create `autobuilder/resources/providers.lua`, `tests/providers_test.lua`;
modify `autobuilder/config.lua`, `tests/run.lua`.

**Interfaces:** `Providers.candidates(item, config)` returns copied descriptors
with stable `id`, `type`, `item`, optional `capability`, `farm`, `recipe`.
`Providers.select(item, config, context)` returns descriptor or nil/reason;
context accepts `available`, `required`, `workers`, `acquisitionOnly`.
`Providers.validatePreferences(map)` validates item -> ordered dense provider-type
lists. `config.providerPreferences` defaults to `{}`. Supported types: storage,
exploration, mining, tree_farm, farm, crafting, smelting.

- [x] Add literal candidate/selection cases for iron, glass, oak logs, two farms,
  stocked demand, configured type preference, offline fallback, and no provider.
  Reject duplicate/unknown types, sparse arrays, invalid item/counts; verify
  returned descriptors cannot mutate config. Run and observe missing module failure.
- [x] Implement registry over existing material/recipe/farm definitions. Require
  compatible resource-filtered mining capabilities; absence of a workers context
  means availability unknown, not all workers offline. Fall back to best configured
  candidate when none currently available so recovery remains possible.
- [x] Add and validate the config field. Register tests in the complete suite.
  Run focused tests and full Lua suite; expected zero failures. Commit.

### Task 10: Explicit aggregated dependency graph

**Files:** modify `autobuilder/blueprint/planner.lua`, `tests/production_test.lua`.

**Interfaces:** `Planner.expand` keeps existing outputs and adds `graph.nodes`:
item-keyed nodes with `required`, `available`, `deficit`, `produced`, `missing`,
`projectRequired`, `provider`, and aggregate `inputs`; operations add `id` and
`dependencies` of earlier producer operation IDs. Node `available` is original physical
stock, not expected output; reserved fuel is included in node demand. Provider metadata is explanatory planning
state; only refreshed physical inventories establish completed acquisition.

- [x] Write cases with two roots sharing planks, intermediate/final stock and
  surplus: aggregate exact demand without treating planned surplus as stock.
  Check operation dependencies precede consumers and fuel shortages are represented.
  Include malformed yield/count, excessive expansion, cycles and substitutions.
  Observe failures before changing implementation.
- [x] Add graph accounting to the existing traversal and bounded validation.
  Reuse provider descriptors; no alternate hardware executor or second queue.
  Preserve old operation ordering and stock/fuel behavior. Run focused and full
  suites and commit after passing.

### Task 11: Provider dispatch, graph visibility and milestone acceptance

**Files:** modify `autobuilder/core/production_service.lua`,
`autobuilder/core/automation_service.lua`, `tests/production_test.lua`,
`tests/automation_runtime_test.lua`; add `docs/resource-planning.md` and update
`README.md`, `docs/fleet-progress.md`, release artifacts.

**Interfaces:** acquisition chooses a provider only when no existing physical
mine/group/harvest job owns the material. Save selected `material.provider` ID;
resume existing jobs using saved geometry. `resource ITEM` returns a readable
summary of selected/candidate providers and current graph demand/stock/deficit.

- [x] Add dispatch cases proving farm preference over mining, online fallback,
  controller restart/offline owner/preference changes retain the original job,
  newly configured farms recover blocked demand and unknown sources stay explicit.
  Add command assertions against real request graph values. Observe failures.
- [x] Route provider choices into existing MINE/HARVEST/FARM paths; use ordinary
  recipe operations for manufactured outputs. Keep the global factory barrier.
  Implement read-only resource summary and document exact config/command usage.
- [x] Run full Lua/Python/release/whitespace checks; use meaningful live dispatch
  acceptance where useful, record exact fixture/limitations. Request final branch
  review, fix reproduced important issues with regressions, commit/integrate and
  continue to inventory ownership and fuel automation without an approval pause.

## Continued execution: inventory ownership prerequisite

**Spec:** [inventory ownership design](inventory-ownership-design.md), fleet
requirements 11–15. Preserve factory exclusivity until dedicated staging exists.

### Task 12: Durable inventory ledger and logical views

**Files:** create `autobuilder/storage/ledger.lua`, `tests/ledger_test.lua`;
modify `tests/run.lua`.

**Interfaces:** `Ledger.new(state,save)` stores `state.inventoryLedger`;
`reserve(id,inputs,outputs,physical,options)` atomically grants or returns nil/reason;
`receipt(id,withdrawn,delivered,transit,sequence)` applies cumulative measured counters;
`release(id)` requires completed outputs and empty transit; `cancel(id)` only
retires unstarted claims. `view(item,physical,demand)` returns physical, available,
reserved, transit, expected, demand; protected reserve passed during grants.

- [x] Add failing cases for competing multi-item claims, duplicate/changed IDs,
  malformed counts, partial/duplicate receipts, offline restart, release/cancel
  guards, unknown physical stock, and rollback on failed/throwing checkpoint.
- [x] Implement bounded maps and transactional persistent mutations; no hardware
  effects or automatic lease expiration. Run focused and full Lua tests; commit.

### Task 13: Factory reservation gates and physical receipts

**Files:** modify `autobuilder/core/production_service.lua`,
`autobuilder/core/workflows.lua`, `autobuilder/core/automation_service.lua`,
`autobuilder/factory/factory.lua`, `autobuilder/factory/crafting.lua`,
`autobuilder/workers/executor.lua`, `autobuilder/core/task_messages.lua`;
add regressions to production/runtime/logistics tests.

- [x] Add failing runtime cases for competing queued claims, no assignment/action
  before grant, partial withdrawal/output reports, delayed duplicates, reboot and
  stock shortfall recovery. Preserve exclusive legacy saved jobs.
- [x] Declare exact inputs/outputs for new factory tasks; grant before dispatch or
  furnace action. Journal crafting withdrawals and send bounded cumulative counts;
  reconcile furnace counters and release only after physical completion. Keep the
  existing factory barrier. Run focused/full suites and commit.

### Task 14: Reservation status and acceptance

**Files:** update resource command/UI, README, progress and acceptance documentation;
regenerate release artifacts.

- [x] Show distinct physical/available/reserved/transit/expected/project demand
  values without counting forecasts as stock. Add command regression assertions.
- [x] Run full Lua/Python/release checks and live furnace/Crafty acceptance. Review
  whole branch, fix reproduced important findings with regressions, integrate and
  continue directly to station staging, fuel distribution and rescue.

## Continued execution: fuel management and rescue

**Spec:** [fuel management design](fuel-management-design.md), requirements 11–12,
24–25. Inventory count claims exist; retain isolation and add station ownership
before new fuel consumers. Native execution remains authorized.

### Task 15: Configurable fuel policy and finite budget primitives

**Files:** create `autobuilder/resources/fuel.lua`, `tests/fuel_test.lua`;
modify config, storage inventory, mining service, worker executor and suite list.

- [x] Add failing validation/budget cases for known/custom fuels, malformed maps,
  thresholds, station identity/geometry, unlimited fuel and insufficient missions.
  Add hardware cases for configured fuel restrictions and lava bucket retention/
  safe depot return; preserve slots 15/16 and existing refuel tests.
- [x] Implement validated fuel policy, estimates and measured native refueling;
  pass config into existing inventory users. No automatic dispatch in this step.
  Run focused/full suites and commit.

### Task 16: Dedicated station ownership and automatic replenishment

**Files:** add controller fuel service and its tests; extend automation/runtime,
workflows, telemetry and inventory coordination. Setup sharing is handled with
operator configuration and visibility in Task18.

- [x] Add failing runtime cases for empty stations, stock claims/capacity, failed
  saves and ambiguous transfers, offline worker, duplicate/partial delivery and
  low-fuel idle worker automatically obtaining fuel before mining assignment.
- [x] Persist station ownership and use the shared controller inventory lock.
  Grant preferred-worker REFUEL only after reconciled filling; hold mining while
  refuel is pending. Replenish stock through ordinary resource requests and show
  explicit bootstrap shortages. Run suites and commit.

### Task 17: Fuel delivery and stranded-worker recovery

**Files:** extend task/message/telemetry validation, worker recovery and courier
executor; add rescue service tests and full-chain recovery scenario.

- [x] Add failing frozen-target/finite-courier cases with partial pickup/delivery,
  full receiver, lost acknowledgements, controller/worker reboot and blocked route.
- [x] Implement bounded identity-checked rescue handshake and measured fuel
  delivery without replacing the original worker task. Reserve pickup/capacity,
  deny unsafe courier missions, resume only known fuel-blocked work and return the
  courier before releasing ownership. Run suites and commit.

### Task 18: Fuel visibility and native acceptance

- [x] Expose fleet fuel budgets, station stock, waiting deliveries and recovery
  status with actionable errors; document exact setup and configurable providers.
- [x] Run full Lua/Python/release checks and native zero-fuel depot plus stranded
  worker acceptance. Review branch, fix demonstrated bugs with regressions,
  integrate and continue to remaining parallel factory/schematic/chunk/recovery
  requirements without a routine approval pause.


## Required continuation: dynamic scaling and automatic site preparation

Added 2026-10-03 under [requirements44–45](fleet-requirements.md#44-dynamic-fleet-scaling).
These extend the full-fleet completion criteria. Keep Tasks16–18 moving; they
provide fuel and recovery prerequisites. Then extend the existing queues and
leases in this dependency order, alongside the remaining original requirements:

- [ ] Complete pickup/destination capacity, independent factory staging and
  parallel crafting/hauling. Expose measured delivery/production rates and
  bottlenecks; forecasts must remain distinct from physical stock.
- [ ] Extend schematic analysis with explicit required air, intended foundation
  coordinates/elevations and access workspace. Preserve intentional multiple
  elevations; do not infer a single flat plane over a terraced design.
- [ ] Survey the full footprint and working area. Plan high-terrain excavation,
  low-terrain fill and remaining-volume clearance from measured world state.
  Select suitable available fill, and route shortages through normal acquisition.
- [ ] Partition preparation and construction into safe owned regions with
  dependencies, worker/route exclusion and infrastructure protection. Use the
  existing durable job/region ownership; never expire an offline physical owner.
- [ ] Implement measured excavation/fill/clearance with changing-terrain rechecks,
  exact obstruction diagnostics, preservation of correct partial structures and
  verified foundation/preparation gates before dependent structural placement.
- [ ] Add bounded workload allocation for mining, hauling, crafting, clearing and
  building: configurable role minima/maxima, outstanding work, measured yield and
  rates, travel cost, supply coverage and independent ready regions. Use suitable
  registered idle workers before saturation; release excess workers at safe task
  boundaries. Provision workers only if automatic deployment is implemented.
- [ ] Expose active/idle counts, queue depth, work remaining, throughput,
  bottlenecks and scaling decisions. Exercise sustained workload and drainage,
  avoiding repeated role switching and duplicate physical work.
- [ ] Test one-to-many ramp-up and scale-down, shared-material mining, parallel
  clearing/building, slopes/hills/holes/caves/water, required air, falling blocks,
  protected terrain and partial builds. Include checkpoint and message failures.
- [ ] Run native acceptance on a sufficiently large uneven site: idle miners,
  clearing turtles and builders join automatically, survey and level/fill the
  footprint, clear obstructions, verify regions, construct, verify and repair.
  No manual preparation or worker assignment. Document measured results and
  remaining limits, integrate and continue all other unfinished requirements.

Required region pipeline: survey → determine foundation elevation → plan site
preparation → reserve regions → excavate high terrain → fill low terrain → verify
level foundation → clear remaining volume → verify prepared regions → build →
verify final structure → repair defects. Independent regions may overlap in time
when their dependencies and physical access permit it.

## Milestone0.16: capacity and independent parallel factory

Spec: [parallel factory design](parallel-factory-design.md). Continue inline under
standing authorization; no milestone handoff pause.

### Task 19: Durable physical capacity reservations

**Files:** `autobuilder/storage/capacity.lua`, `tests/capacity_test.lua`, suite list.

- [x] Add failing tests for concrete-slot reservations, shared and exclusive claims,
  measured stack/slot bounds, unknown item limits, immutable duplicates, reboot,
  failed save rollback, full/missing destinations and explicit release.
- [x] Implement native measured-capacity planning and durable ownership. Run focused
  tests and full suite; commit. Expected: no owner can reserve the same capacity.

### Task 20: Private Crafty station contracts and execution

**Files:** config, worker capability/task validation, Crafty executor, workflows,
production receipts, focused runtime tests.

- [x] Add failing incompatible-station, private-buffer-only, completed/collecting
  and duplicate-progress cases. Validate unique inventories and worker ownership.
- [x] Implement capability-gated private station execution and durable worker-finish
  acknowledgement without central output credit. Legacy execution stays exclusive.
  Run tests and commit. Expected: workers cannot mutate shared stock in this mode.

### Task 21: Controller staging and parallel batch scheduling

**Files:** parallel factory service, production planner/service, workflow integration,
full runtime fixture with two independent Crafty turtles.

- [x] Add failing parallel/splitting, short stock, partial stage/collection, missing
  capacity, controller/worker restart, lost ack and independent blocked-station cases.
- [x] Reserve inputs/private stations/output slots; journal staged inputs and final
  collection; split exact finite operations across idle eligible stations. Release
  only reconciled complete jobs. Run full tests and commit. Expected: two workers
  craft concurrently with conserved quantities and no duplicate production.

### Task 22: Parallel factory native acceptance and integration

- [x] Document configuration, ownership, bottlenecks, measured rates and limitations.
  Run native two-Crafty acceptance with finite batches and restart. Correct defects
  with failing regressions. Run all Lua/Python/release checks, one whole-branch
  review and required fix pass, integrate/push, then continue remaining requirements.

## Milestone0.17: native schematic entry

Spec: [native schematic design](native-schematic-design.md). Native execution
continues under standing authorization. Interfaces: bounded gzip bytes feed typed
NBT conversion, which feeds the existing validated schema1 project pipeline.
Review focus: decompression bombs/truncation, incorrect NBT tag types, source
mutation during import, repeated shorthand after restart, unsupported metadata.

### Task 23: Bounded native gzip decoding

**Files:** `autobuilder/blueprint/gzip.lua`, `autobuilder/vendor/libdeflate.lua`,
`autobuilder/vendor/README.md`, `tests/native_gzip_test.lua`, suite list/fixtures.
**Interface:** `gzip.decode(bytes,maxBytes)` returns decompressed bytes or throws
before any physical effect; raw NBT detection belongs to Task24.

- [x] Write/run failing stored/fixed/dynamic gzip, optional-header, CRC/ISIZE,
  trailing/truncated stream and bounded-expansion tests. Expected: missing module.
- [x] Vendor pinned LibDeflate with license and a marked bounded/progress hook;
  implement strict gzip wrapper and cooperative loops. Run focused/full Lua tests;
  expected all pass. Commit independently usable bounded decoder.

### Task 24: Typed NBT and native Sponge conversion

**Files:** `autobuilder/blueprint/nbt.lua`, `autobuilder/blueprint/sponge.lua`,
`tests/native_schematic_test.lua`, Python fixture generator/comparison tests.
**Interfaces:** `nbt.decode(bytes)` returns typed root compound;
`sponge.decode(bytes)` returns validated schema1, using Task23 for gzip detection.

- [x] Write/run failing raw/gzip versions2/3, offset/palette/state/required-air,
  paired/slab quantities, entities/biomes and malformed tag/length/depth/node/
  dimension/varint cases. Expected: missing modules, no partial blueprint.
- [x] Implement bounded typed parsing and schema1 conversion; reuse quantity and
  schema validation. Run native Lua and Python differential tests; expected equal
  blueprint values and precise refusal. Run full suite and commit.

### Task 25: Native import commands, live acceptance and integration

**Files:** schematic loader, projects/command help, import/runtime regressions,
operator documentation, `docs/validation-0.17.0.md`, progress ledger, release.

- [x] Add failing binary import/shorthand/duplicate/reboot/source-change tests,
  ensuring invalid files or unsupported analysis cannot start physical work.
- [x] Implement binary read/immutable JSON normalization and `.schem` shorthand;
  retain existing JSON behavior. Run focused/full Lua and Python tests.
- [x] Run native gzip-schematic construction/verification and independent world
  inspection. Fix discovered bugs with regressions. Document exact evidence and
  limits, generate/check release, conduct one final whole-branch review/fix pass,
  integrate/push and continue chunk loading and every remaining requirement.

## Milestone0.18: loaded mission compatibility

Spec: [chunk-loading design](chunk-loading-design.md). Continue native execution.
Review focus: claiming future loading from a heartbeat, negative chunk boundaries,
coverage omitted on a return/supply route, offline-loader reassignment, persisted
jobs admitted after configuration changes. Test each at the owning boundary.

### Task 26: Coverage geometry, hardware and durable provider claims

**Files:** `autobuilder/core/chunks.lua`, config, `tests/chunks_test.lua`, suite list.
**Interfaces:** `chunks.area(job,telemetry)` returns a conservative bounded chunk
rectangle; `chunks.new(state,config,save)` provides `reserve(job,worker)` and
`release(jobId)`; `chunks.probe(environment,state,config)` reports actual stationary
chunky hardware. Shared pure validators serve telemetry/assignment integration.

- [x] Write/run failing boundary, missing/dead/moving-provider, explicit-area,
  configured-anchor-without-hardware, exact duplicate, save rollback/reboot and
  release tests. Expected: missing module or coverage refusal, no physical work.
- [x] Implement default enforced policy, bounded mission geometry and immutable
  durable claims using configured areas or current-chunk anchors. Run focused/full
  Lua tests; expected all pass. Commit reusable coverage contract.

### Task 27: Queue admission, worker guards and protocol integration

**Files:** runtime, workflows/mining queues, network/task/mining messages, agent,
executor/navigation, setup sharing, runtime tests and explicit loaded test fixtures.

- [x] Add failing covered/uncovered simultaneous work, old worker, depot/side-route,
  changed duplicate grant, offline loader, default-deny movement and reboot tests.
  Expected: uncovered work cannot create movement intent or acquire an owner.
- [x] Wire coverage claims before assignment, preserve them through reconciliation,
  validate/clean loaded envelopes, advertise real anchors and prevent reassignment.
  Add movement enforcement separate from traffic reservations. Existing simulations
  explicitly declare their loaded terrain; no production test-only bypass.
- [x] Run relevant/full Lua and Python tests, fix regressions and commit. Expected:
  covered independent work continues; unknown territory reports exact chunk errors.

### Task 28: Chunk status, setup, native loading acceptance and integration

- [x] Document operator assurances, anchor setup, migration, radius0 coverage and
  lost-provider recovery; expose status and share policy without anchor roles.
- [x] Bootstrap distant real chunky anchors, remove operator force loading and
  verify retained ticking plus a cross-chunk mission and uncovered-area refusal.
  Correct defects with regressions and record independent world evidence.
- [x] Run all tests/release checks, one final whole-branch review and required fix
  pass. Integrate/push and continue recovery/logistics/scaling/site preparation and
  every other unfinished requirement without a milestone handoff pause.

## Milestone0.19: physical logistics and infrastructure nodes

Spec: [logistics design](logistics-design.md). Native inline execution continues.
Review focus: mixed-stock suction, changed endpoints after reboot, factory/haul
starvation, final slot overbooking and stale worker completion. Each is exercised
below. Reuse count/capacity ledgers and private transfer journals; no dependencies.

### Task 29: Registered nodes and protected ownership

**Files:** `autobuilder/storage/nodes.lua`, config/runtime, exploration protection,
`tests/logistics_nodes_test.lua`, suite list.
**Interfaces:** `nodes.validate(config)`, `nodes.validateSaved(config,state)`,
`nodes.get(config,id)`, `nodes.protected(config,state)` return validated identities
and physical exclusion boxes. Saved jobs use `logistics={source=node,
destination=node,pickup=buffer,drop=buffer}` immutable snapshots.

- [x] Add/run failing dense bounded schema, inventory alias, protected stock/stand,
  saved rebind/removal and unrelated-node edit tests. Expected missing contract.
- [x] Implement validated node configuration and held-job protections; reuse existing
  station ownership guard. Run focused/full Lua tests; expected pass. Commit.

### Task 30: Reserved finite transport batches and measured receipts

**Files:** `autobuilder/core/logistics_service.lua`, production/automation/workflows,
worker courier/executor, task messages/config, `tests/managed_logistics_test.lua`.
**Interfaces:** `logistics.new(app,config,e,queue,production)` exposes
`request(item,count,sourceId,destinationId,key)`, `tick()`, `step()`, `describe()`;
production invokes step under its inventory lock and synchronizes central receipts.

- [x] Add/run failing exact stock/capacity/private-buffer claims, mixed input,
  partial staging/collection and two-hauler cases. Expected no managed service.
- [x] Implement finite batch selection, immutable contracts and capability gating;
  staged readiness, measured worker counters and collecting completion. Add/run
  restart-after-stage/suck/drop/collect, duplicate counter, offline-owner and
  changed-contract cases. Expected conserved inventory and retained ownership.
- [x] Exercise existing active factory drainage and pending shortage without
  deadlock; no shared effect while another journal is unresolved. Fix regressions,
  run full Lua/Python tests and commit complete transport execution.

### Task 31: Automatic restocking, commands and native acceptance

- [x] Add/run failing desired-stock routing, inbound subtraction, source ranking,
  capacity-sized batches and production-shortage/restart cases. Implement using
  Task30 API and existing resource graph; expose `haul` and `logistics` status.
- [x] Run native two-courier finite-stock acceptance with both restarts and a
  temporarily unavailable endpoint. Inspect actual inventories and durable claims;
  correct bugs with regression tests and document results/limits.
- [x] Run all Lua/Python/release checks, one whole-branch review/fix pass. Update
  running progress, integrate/push and continue all unfinished requirements.

## Milestone0.20: automatic pose recovery

Spec: [pose recovery design](pose-recovery-design.md). Native inline execution.
Review focus: accepting unexpected GPS relocation, replaying a probe after physical
success, clearing another worker's traffic cells, resuming unrelated/paused work,
and acting outside a saved loaded grant. Preserve every physical engine journal.

### Task32: Evidence-bounded reconciliation and task resumption

**Files:** navigation/runtime, worker executor/mining service, chunk guard,
`tests/pose_recovery_test.lua` and runtime regressions.
**Interfaces:** navigation.reconcile(fix,heading) validates pending geometry; explicit
heading remains operator override. Executor/miner poseRecovered resumes only recorded
pose-related blocks after a complete trusted pose.

- [x] Add failing from/to/unexpected GPS, turn heading, checkpoint failure, interrupted
  task resume, unrelated block, pause and disabled-policy saved-grant regressions.
- [x] Implement bounded reconciliation and shared runtime pose-block lifecycle. Run
  focused/full tests; commit completed recovery foundation.

### Task33: Durable guarded heading probe

**Files:** recovery driver, workflows/automation, task protocol/runtime, tests.
**Interfaces:** one atomic recovery-cell grant keyed by owner/task/sequence/origin;
worker probes once with persistent intent and derives heading from actual GPS delta.

- [x] Add failing all-neighbor ownership, exact duplicate, coverage/protection,
  competing worker, checkpoint rollback and reboot tests. Implement atomic claims.
- [x] Add failing physical probe/reboot/no-GPS/no-fuel/obstacle/receipt tests and
  actual runtime task continuation; implement driver and validated protocol.
- [x] Run focused/full tests and fix regressions. Commit complete autonomous recovery.

### Task34: Native interrupted-action acceptance and integration

- [x] Build real GPS fixture; inject post-effect reboot for translations/turns and
  verify automatic original-task completion with actual world/inventory evidence.
- [x] Record limits and failures, regression-test fixes, update commands/status/docs.
  Run full Lua/Python/release checks, one whole-branch review/fix pass, integrate/push.
- [x] Continue final settlement, continuous supply, scaling/site preparation and all
  other unfinished fleet requirements without a milestone handoff.

## Milestone0.21: capacity-aware crafting batches

Spec: [adaptive crafting design](adaptive-crafting-design.md). Standing authorization
continues native inline execution. Keep finite owned contracts immutable; size only
unclaimed work. Review boundaries: cancelled offset coverage, failed atomic grant,
worker ownership, unavailable candidate and native unknown output stack sizes.

### Task35: Read-only capacity sizing

- [x] Add failing preview/no-mutation, cached observation, native limits and held-slot
  tests. Extract the existing allocator so reservation and preview use one algorithm.
- [x] Implement bounded cached observations and largest-fit batch evaluation; preserve
  strict quantities, unknown limits and concrete allocations. Run focused tests.

### Task36: Atomic adaptive grants and operation coverage

- [x] Reproduce pane output stall, worker pinning and legacy unstarted claims. Implement
  atomic count/capacity/quantity grants, first-gap scheduling and safe legacy retirement.
- [x] Exercise simultaneous stations, small inputs, changed availability, failed saves,
  partial transfers and runtime restarts. Run full Lua/Python/release gates and commit.

### Task37: Native pane acceptance and integration

- [x] Run real two-Crafty high-yield production without an output sample. Verify exact
  source/output/private inventories and final claims; record bugs/limits/regressions.
- [x] Update documentation, run final checks and one whole-branch review/fix pass,
  integrate/push and continue every remaining fleet requirement.
