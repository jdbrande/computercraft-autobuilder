# 0.18.0 loaded mission acceptance

Scope: explicit loaded-area admission and movement enforcement using assured
rectangles or stationary Advanced Peripherals chunky turtles. This establishes
compatibility with real chunk-loading infrastructure; automatic anchor manufacture
and deployment are not claimed.

## Automated evidence

- Six geometry/provider/checkpoint cases failed before implementation, then passed;
  Task26 full suite:514 Lua tests.
- Twelve runtime cases cover independent covered dispatch, missing terrain, old
  workers, atomic ownership/save rollback, depot/approach envelopes, movement before
  intent, immutable grants, reboot, offline providers, legacy recovery, private
  collection and preserving active limits after opt-out. Task27:526 Lua/18 Python.
- Three status/setup regressions failed then passed. Pre-review full gate:529 Lua
  tests,18 Python tests, release0.18.0 generation/check and whitespace check passed.

Existing hardware simulations explicitly declare their in-memory loaded terrain.
Production defaults enforce coverage and assume no loaded area. Fixed miners need
known bounds; envelopes use floor division for negative coordinates and a two-block
horizontal margin, capped at1024 chunks. New assignments require the coverage
protocol. Provider claims and worker assignment share one checkpoint. Worker guards
run before movement intent, separately from traffic reservations.

Integration caught failed-save ownership/geometry leftovers and missing historical
coverage after queue recovery. Regressions cover both. Restored physical owners
remain owned; explicit assured geometry is required to establish a missing legacy
movement contract. Private crafting retains provider claims through collection.

## Native Minecraft — 2026-10-03

World `TESTINMG`, Minecraft1.20.1, Forge47.4.10, CC:Tweaked1.120.0, Advanced
Peripherals0.7.48r. Controller142, builder/courier143 and stationary anchors140/141
used a distant rig around `(1028..1052,299..301,1032..1038)`, away from the player.
Each turtle started with finite2000 fuel. Both anchors had actual chunky and
wireless upgrades. The installed AP radius remained0 and expiry remained600 seconds.
Every fixture configuration enforced coverage with an empty assured-area list.

The operator temporarily force-loaded chunks `(64,64)` and `(65,64)` to construct
and start the rig, then removed both vanilla tickets before construction. Vanilla
`forceload query` showed only the observer chunk `(4,-1)`. Independent `execute if
loaded` checks confirmed both distant fixture chunks remained loaded, including
later checks. Runtime snapshots continued to advance throughout the trial. Actual
peripheral detection advertised the anchors at their corresponding chunk positions.

An intentionally uncovered transport to chunk `(66,64)` stayed queued with no
worker and no coverage lease. Its exact error was
`MISSION_BLOCKED_UNLOADED_AREA: chunk 66,64`. Meanwhile `build /covered.schem`
loaded a gzip Sponge v3 file, acquired supplied central stock, delivered it to the
builder, crossed the chunk boundary and placed four stone bricks at
`(1048..1049,300,1032..1033)`. The controller rebooted during construction. Without
resume or reassignment, the project reached `built` in55.48 seconds and verification
reported4 correct blocks. Independent world commands confirmed all four positions.

The operator then shut down anchor141. After the controller marked it offline,
`build verify covered` created a verification task which remained unassigned with
missing chunk `(65,64)`. Restoring141 and rebooting142 let that same queued task run;
its final report again counted4 correct cells. The `chunks` screen showed two online
anchors, zero assured rectangles and only the intentionally uncovered transport
blocked. All coverage leases were released and all three workers were idle.

Final independent inventory inspection found one of the original five stone bricks
in central stock and an empty supply chest. Anchors retained2000 fuel and their
original positions. Builder143 finished at `(1049,301,1033)` with1906 fuel. This
trial supplies finished material to isolate loading, dispatch, construction and
recovery; fresh mining-to-building remains the separate0.12 evidence. Automatic
final home return remains later fleet work.

All four test computers were shut down. Physical anchors were removed so AP stops
refreshing their tickets; AP stale-ticket expiry is separate from vanilla force
loading and is not assumed immediate. The controller/supply rig and four completed
blocks remain. Ignored evidence under `dist/live-chunks/` includes setup commands,
peripheral/state snapshots, removed-ticket results, continuous state/reboot history,
uncovered/offline refusal, final status, inventory/block inspection and cleanup.
The observer submits normal operator commands; turtles use native APIs.

## Limits

Chunky detection counts only the current chunk and requires a settled stationary
pose. Offline anchors preserve held ownership but cannot admit new work. External
hardware loss can still freeze a worker; no Lua program executes in unloaded
terrain. Wired peripheral names do not reveal infrastructure coordinates: remote
storage, farms and processors must be kept loaded separately until global physical
infrastructure registration is implemented. Modem reach is a separate constraint.

The compatibility boundary accepts bounded covered missions and refuses unsupported
areas. Automatic loader placement, broader routing/recovery, full logistics,
dynamic scaling, automatic leveling and large-fleet acceptance remain mandatory
subsequent work in the fleet requirements.
