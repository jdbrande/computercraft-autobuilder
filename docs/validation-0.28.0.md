# Continuous production and construction candidate validation

Accepted0.28.0, implementation `b7f3f87`. Native acceptance and complete release
gates passed. The full fleet roadmap remains unfinished.

## Automated evidence

-853 Lua tests passed on the final implementation.

-18 Python tests pass. Release generation/verification and whitespace checks pass.
- Actual controller, miners, furnace, crafter and two builders demonstrate a
  successful placement call while another miner is away on active acquisition.
  Independent regions have a four-air-cell gap beyond traffic exclusion. The
  prepared fixture survives controller/builder restarts and verifies7 positions:
  two stone bricks, four required air and one glass. Exact receipts reconcile4
  mined cobblestone,1 sand,4 smelted stone,1 glass,4 crafted bricks,3 placements and
  2 surplus bricks, with empty returned workers and closed supply ownership.
- The original cumulative-placement assertion did not establish concurrency. The
  final review reproduced that weakness; its claim was withdrawn and replaced by
  the event-level assertion above, which failed under the serialized fixture.
- The same final review found streaming supply production ignored project pause,
  and a stale stock-only flag could disable new-run acquisition. Regressions cover
  queued and active acquisition pause/reboot/resume with stable request identities,
  ordinary new-run acquisition, and retained active legacy ownership. An inherited
  first-site checkpoint window also has a regression through completed recovery.

## Native Minecraft acceptance — 2026-10-03

PrismLauncher1.20.1 / TESTINMG, Forge47.4.10, CC:Tweaked1.120.0 and Advanced
Peripherals0.7.48r. Controller228, builders229–230, inspection miners231–233 and
Crafty234 formed a wired/wireless fixture near `(1536,300,0)`. Every worker began
with5000 finite fuel. Twenty operator-loaded chunks, private supply/home inventories,
27 stone foundation cells and staged raw deposits were provided. No backup was made.

The seven-position project at `(1560..1566,300,6)` contains two stone bricks, four
air cells and glass. `build level pipeline` first verified independent regions;
`build auto pipeline` then acquired4 cobblestone,1 sand and2 coal, smelted4 stone
and1 glass, crafted4 bricks, placed3 blocks, verified all7 positions and returned
all workers empty. The first run finished without a captured placement/mining
intersection; it is completion/conservation evidence, not the native overlap proof.

The retest removed the three finished blocks and provided another sand and coal
ore deposit. Its two initial bricks were the first run's measured surplus; no
finished building material was supplied by the operator. Ordinary `build auto`
reprepared the workspace. Builder230 placed both bricks while sand miner232 was
away from its depot on active acquisition. Retained runtime reports identify the
brick placements, successful placement attempts and actual inspected block names;
the acquisition snapshot places the miner at `(1627,300,0)`. Controller228 and both
builders then rebooted. The project completed with another glass and all7 positions
correct. All three finite production requests across both runs completed.

Independent observer90 performed60 final checks: seven structure positions,27
foundation cells, eleven storage/furnace observations, six turtle observations and
nine removed raw-deposit cells. All passed. Final central/private inventories and
worker cargo were empty; the furnace recorded4 stone and2 glass across both runs.
Across the two builds,4 crafted bricks and2 glass were placed (the first three
blocks were deliberately removed for the retest). No active mining trip, supply
owner or held stock/capacity lease remained.

Final finite fuel for workers229–234 was4096,4114,4950,4928,4908 and5000. Both
builders and all miners returned to their configured depots. Computers228–234 were
shut down, twenty fixture force-load tickets removed, and the passive monitor
stopped. Player position was unchanged. Ignored `dist/live-continuous-pipeline/`
contains setup, per-step state observations, first-run checks, overlap/restart
snapshot, retest completion, final world observations and cleanup receipts.

## Limits

The staged native envelope and prepared independent regions establish this small
pipeline boundary. They do not prove arbitrary terrain, automatic chunk loading,
large fleet network performance or every remaining placement/provider capability.
Each builder waits during its own replenishment; other workers provide overlap.
Explicit prepare/start and saved legacy full-stock requests retain their behavior.
