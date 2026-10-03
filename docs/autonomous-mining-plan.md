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

**Execution:** All eight tasks implemented on `feature/autonomous-exploration`.
The final independent review produced eight findings, addressed in one regression
fix pass. Final evidence: 405 Lua tests; 16 Python tests run, one skipped;
release checks passed. See [validation and live checklist](validation-autonomous-mining.md).
Live Minecraft acceptance and branch integration remain pending. The operating
guide records the exclusive-corridor and bounded-detour implementation decisions.

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

- [ ] Add tests for disabled defaults, mode-specific required settings, negative
  coordinates, clipping, 4096-sector acceptance, 4097-sector rejection, stable IDs
  after expansion, deterministic ordering and route/protection conflicts. Expanding
  a previously clipped edge sector must expose its newly added cells for survey
  without discarding the old cursor or changing an already-owned trip's geometry.
- [ ] Run the suite and confirm the new module/config contract is the failure.
- [ ] Add `mining.mode='fixed'|'explore'` with fixed default and optional dense
  `mining.exitRoute`. Add exploration configuration with enabled=false by default;
  enabled configurations require base, envelope bounds, dimension bounds and base
  protection. Validate the explicit schema rather than allowing arbitrary keys.
- [ ] Implement the geometry functions with existing `pathfinding.find`. A route
  consists of adjacent coordinates from the depot exit to the sector entry;
  depot exits are declared already-clear traversal only. Cap route entries at
  `min(floor(maxTravelDistance),1024)` for bounded messages. Reject a mission whose
  outward route and return cannot fit fuel plus reserve; work uses a live return
  threshold. Unlimited fuel still respects geometry and route length limits.
- [ ] Verify tests pass; commit this independently testable geometry/config change.

### Task 2: Negotiated exploration assignments and reports

**Files:** Modify `autobuilder/workers/agent.lua`, `autobuilder/core/network.lua`,
`autobuilder/core/mining_messages.lua`, `autobuilder/config.lua`,
`tests/network_test.lua`, `tests/resources_test.lua`.

**Interfaces:** Existing `MiningMessages.validate(kind,p)` and `clean(kind,p)`
accept optional assignment `p.exploration` from the data contract. Progress adds
`p.exploration={result,cursor,observations,clearedRouteCount}`. Add `mine_return`
carrying only `jobId` to request a safe return. Existing envelopes remain version 1;
the new assignment payload is explicitly versioned and capability-gated.

- [ ] Add round-trip tests for valid exploration telemetry/assignment/progress and
  rejection tests for sparse/cyclic routes, nonadjacent waypoints, false coordinates,
  out-of-envelope entries, excessive observations, unknown results and legacy
  packets acquiring exploration fields through unvalidated copying.
- [ ] Run and observe the new protocol assertions fail.
- [ ] Validate dense lists before copying; route cap is 1024, observation cap 64 per
  report, sector axes at most 8/3/8. Check finite integers, bounded strings and
  geometry membership. Copy only known validated fields. Preserve old telemetry
  and fixed mining messages byte-for-field where unchanged.
- [ ] Advertise exploration support and home geometry from valid worker config;
  keep ordinary capabilities independent of role labels. Return unknown or
  malformed exploration data as an error, not an unrestricted legacy assignment.
- [ ] Verify tests pass; commit protocol and capability negotiation.

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

- [ ] Add tests where a demand of 128 and two capable workers produces two disjoint
  64-item trips. Assert unavailable/offline workers retain claims, zero/partial
  results leave the group open, duplicated reports do not alter credited counts,
  and failed saves produce no dispatchable ownership.
- [ ] Add delayed-report cases: stock increases before progress, incidental drops
  satisfy another material, stock refresh fails, and a partial result arrives after
  a restart. Assert no new quota exceeds uncovered demand and conservative waiting
  ends after reconciliation. Also test duplicate request keys and legacy groups.
  Temporary route/sector ownership conflicts must produce waiting, not permanent
  inaccessibility or search-envelope exhaustion.
- [ ] Run and confirm these tests fail for the missing acquisition behavior.
- [ ] Implement quota allocation from refreshed stock minus outstanding undelivered
  quotas. Choose geometry using task 1 and require the task 2 capability. Persist
  the trip, group linkage and original quota atomically before returning a job.
  Respect the existing factory barrier and workerBusy checks across both queues.
- [ ] Accept terminal partial results only for a saved exploration owner, retain
  transfer uncertainty, and complete a group only with enough stock and no owned
  physical trips left to reconcile. Exhausted or inaccessible candidates produce
  visible shortfalls. Revisit only an unfinished cursor or newly permitted sector.
- [ ] Verify tests pass; commit acquisition accounting and assignment.

### Task 4: Physical exploration and journaled excavation

**Files:** Modify `autobuilder/resources/miner.lua`,
`autobuilder/resources/exploration.lua`, `tests/miner_test.lua`, `tests/world.lua`.

**Interfaces:** Preserve `Miner.new(task,hw,config,nav,inventory,scanner,save,clock)`.
For `task.exploration`, use saved assignment geometry and mutable
`task.explorationProgress={cursor,observations,clearedRouteCount,result}`.
Add executor `requestReturn() -> true | false,reason`; keep `step()` and `resume()`.

- [ ] Add physical-world tests for excavation on the explicit access route, a
  partial survey followed by return, cursor persistence across unloading, full
  cargo, finite fuel, optional scanner and inspection-only operation. Assert
  unrelated cells and protected exits are never dug.
- [ ] Inject failure immediately before/after dig, movement and deposit. Include
  falling gravel, waterlogged blocks, a changed tool slot, foreign item metadata,
  and an obstacle on return. Assert exact observed delivery or a preserved blocked
  intent; never repeated unbounded digs, spillover to slots 15/16 or false success.
- [ ] Run and establish the failing physical regressions.
- [ ] Limit dig permission to the assigned sector and access route. A clear exit
  permits traversal only. Reuse scanner and inspection fallback; survey each
  sector layer so a saved survey cursor describes the actual pattern attempted.
  Keep observed targets and confirmations bounded using task 3's record format.
- [ ] Journal exploration digs using the existing site's before/after block and
  inventory approach, adapted to allowed mining drops. Unreconciled outcomes block.
  Require new inspection after each falling block and cap retries at the existing
  site-clearing bound of four; never infer a clear target from dig's return alone.
- [ ] On trip end, retrace the saved trail, unload measured cargo and expose the
  terminal reason. Low fuel and full cargo are partial trip results after unloading;
  blocked return remains nonterminal. Fixed-box mining retains existing behavior.
- [ ] Verify tests pass; commit the executor and recovery behavior.

### Task 5: Runtime dispatch and crash recovery

**Files:** Modify `autobuilder/core/mining_service.lua`,
`autobuilder/core/runtime.lua`, `autobuilder/core/receipts.lua` if receipt shape
requires it; extend `tests/mining_runtime_test.lua`, `tests/receipts_test.lua`.

**Interfaces:** Retain current service `tick`, `step`, `handle` entry points.
Send the task 2 fields from saved jobs; instantiate task 4 with the original
payload. Completed exploration receipts retain delivered count and terminal
survey result so acknowledgements can be retried without repeating physical work.

- [ ] Add runtime tests for dropped assignments, dropped terminal reports/acks,
  duplicate dispatch with different geometry, controller/worker restarts during
  partial unloading, and backup recovery missing the original assignment.
- [ ] Assert a changed local fixed mining box does not rewrite an exploration
  assignment, old receipts still replay correctly, and an offline owner cannot be
  replaced merely because its heartbeat expired. Run and observe failures.
- [ ] Wire validated assignments and reports through existing transport. Worker
  duplicate acceptance compares the immutable exploration geometry too. Restore
  active saved exploration execution even if new exploration dispatch is disabled.
- [ ] Extend safe receipt retirement to group/trip references and acknowledged
  survey state. Never delete a trip while production references it or worker
  telemetry still reports it. Keep bounded historical receipts and confirm backup
  recovery cannot recreate a lease from a worker's unsupported claim.
- [ ] Verify tests pass; commit runtime/recovery integration.

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

- [ ] Add tests proving registered mining resources choose exploration when
  configured, farms still use HARVEST/FARM, recipes still use production operations,
  and no capable explorer yields an actionable blocked reason.
- [ ] Add project-import overlap, paused outbound mission, disabled exploration,
  missing stock, and outstanding unload tests. Assert no factory starts before
  every affected physical miner has returned and reconciled. Run and observe failures.
- [ ] Use the existing resource request -> acquisition -> physical-job boundary;
  tag the exploration provider without introducing a generic registry prematurely.
  Aggregate each group's workers and shortfall into the existing material status.
- [ ] Build protected boxes from transformed imported volumes and known stations,
  including standing/overhead clearance used by current build routes. Treat the
  configured base protection and explicit infrastructure boxes as dig exclusions.
  Refuse project/config mutations conflicting with owned work before saving them;
  never authorize a protected-area dig to recover progress.
- [ ] Preserve explicit cleared exit traversal without weakening the global
  navigation restrictions: the exploration route admits only its prevalidated
  clear-exit cells, and the dig guard still rejects them. Unknown return pose or a
  newly invalid route stops with a recovery explanation.
- [ ] Verify tests pass; commit pipeline/protection/pause integration.

### Task 7: Operator setup, status and bounded expansion

**Files:** Modify `autobuilder/setup_wizard.lua`, `autobuilder/setup_share.lua`,
`autobuilder/core/mining_service.lua`, `autobuilder/ui/ui.lua`,
`tests/setup_test.lua`, `tests/mining_runtime_test.lua`; add
`docs/autonomous-mining.md` and update `docs/material-team.md`.

**Interfaces:** Add `setup exploration` on the controller and
`setup miner explore` on a worker, preserving resource-profile setup.
Controller commands: `exploration status`, `exploration expand <radius>`,
`exploration pause`, `exploration resume`.

- [ ] Add setup transcript tests for valid save, cancel, missing depot/pose, bad
  exit routes, conflicting protection, invalid dimension bounds and active jobs.
  Add command tests for expansion that preserves IDs, shrink rejection, 4096-sector
  limit and keeping offline ownership. Run and observe failures.
- [ ] Reuse setup's transactional settings save. Prompt for the base, operating
  boundary, loaded-area assumption, infrastructure protection and declared clear
  exits; display coordinates before saving. Do not move or consume fuel merely to
  detect hardware. Require known heading when it cannot be established.
- [ ] Show material target/live stock, all owners, sector/cursor, trip quota,
  state/fuel and actionable shortfalls. Keep existing screens usable on small
  terminals. Log assignments, partial deliveries, exhaustion and recovery using
  the existing logger, without flooding normal screens.
- [ ] Explain exactly how to place/connect deposit chests, provide startup fuel,
  configure exits, keep the envelope loaded, import the current JSON schematic
  format and run `build auto NAME`. Clearly label direct `.schem` commands and
  automatic fuel rescue as later requirements, not implemented commands.
- [ ] Verify tests pass; commit setup, commands and operating documentation.

### Task 8: Full acquisition to verified construction and release checks

**Files:** Extend `tests/autonomous_chain_test.lua` and its local `fixture(options)`;
modify `README.md`, `docs/autonomous-mining.md`; add
`docs/validation-autonomous-mining.md`; regenerate `manifest.json` and
`installer.lua` with the existing release tool after source changes stabilize.

**Interfaces:** Extend the existing local fixture with
`options.exploration`, `options.scanner`, `options.finiteFuel` and
`options.restartAt`; retain existing defaults and existing tests.

- [ ] Add a small-project test with two explorers sharing cobblestone demand, raw
  coal/sand discovered in other sectors, no configured deposits, and no preloaded
  finished building blocks. Assert distinct ownership, an empty first-sector result,
  real deliveries, furnace/crafting output, exact placement and clean verification.
- [ ] Repeat with inspection fallback and finite fuel; inject controller/worker
  restarts plus lost terminal acknowledgements. Assert every worker is accounted
  for and no active exploration claim or unresolved transfer remains. Establish
  that the new acceptance tests initially fail on the missing integration.
- [ ] Fix only demonstrated integration gaps; preserve the original autonomous
  chain and pilot tests. Record resource/fuel fixture setup so results do not imply
  fuel distribution or chunk-loading support that was not implemented.
- [ ] Run `.venv/bin/python tests/run.py` and
  `python3 -m unittest discover -s tests -p 'test_*.py'`. Require successful exits
  and inspect any skips. Record new counts from output, not this plan.
- [ ] Generate a 0.12.0 candidate with
  `python3 tools/release.py --version 0.12.0`, then run
  `python3 tools/release.py --check`, the installer tests in the Lua suite and
  `git diff --check`. Keep the existing release base URL; do not publish or update
  live computers as a side effect of generating artifacts.
- [ ] Write the validation record and live checklist: loaded test area, two miners,
  one crafter, furnace/storage and one builder; second-sector selection, partial
  delivery, pause/return, reboot recovery and verified construction. Mark the live
  trial pending unless it actually ran in Minecraft. Commit the verified candidate.

## Execution handoff

Native execution is recommended because the protocol, ownership, physical actions
and recovery contracts share state and benefit from one implementation context.
Review this plan and choose native or subagent-driven execution before code work.
After implementation, run a whole-change review and resolve reproduced issues.
Implementation completion and live Minecraft acceptance must remain separate claims.
