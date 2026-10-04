# 0.34.0 container metadata and sign geometry acceptance

Accepted source `3cd7f70` passed **956 Lua tests**, **20 Python tests**, release
and diff checks, including inherited0.33 ascent and paired-checkpoint corrections.
The native acceptance below and final-source gates completed before integration.
Final logs: `/tmp/fleet-034-final-full-v3.log` and corresponding Python evidence.

## Automated evidence

- 20 Python tests passed, including malformed NBT tag types and omitted Sponge v3
  `Data`, with native/Python normalization parity.
- Focused metadata, placement, protocol and actual project regressions passed.
  Real modules prepare/build/verify empty containers through supply and restart,
  detect inserted contents without digging, and retain standing-sign grass support.
- Release generation/check and diff checks passed on the final implementation.
- One final review and consolidated regression fixes covered written-sign repair,
  grass support, trapped-chest entity identity, typed NBT parity and optional v3 data.

## Native Minecraft acceptance — 2026-10-03

PrismLauncher 1.20.1, `TESTINMG`, Forge 47.4.10, CC:Tweaked 1.120.0 and Advanced
Peripherals 0.7.48r. Controller 247 and builder 248 use wired stock/depot/supply
inventories 1016–1018. The builder starts with 20,000 finite fuel. Four operator
force-loaded chunks cover the separate fixture; no world backup was created.
Finished placement items were stocked explicitly: this checks import/preparation/
placement/verification, not raw-material production or automatic chunk loading.

Native probes confirmed cardinal chest/furnace facing, upright/horizontal barrels,
cardinal standing/wall signs and readable empty container inventories. `placeUp`
still produces an upward barrel; downward barrels are explicitly unsupported.
Signs expose no peripheral text reader, so only geometry is supported and every
sign block-entity payload is rejected. An independent block-data query confirmed
`minecraft:trapped_chest` as the actual trapped chest block-entity ID.

The first JSON project placed nine target cells at `(2160..2168,300,6)`: east-facing
single chest, upright barrel, south-facing unlit furnace, east-oriented standing
and wall oak signs, their stone support, and three air cells. Fixture inventory
names and a cable bypass were corrected before placement. An immediate test reboot
after the first placement interrupted a turn; runtime correctly retained ambiguous
pose and blocked work. Independent world-facing checks supported an explicit
operator pose confirmation. The project then completed and all nine independent
world checks passed. This run is assisted, not automatic ambiguous-turn recovery.

A clean second project, `metadata_native`, imported an actual gzip Sponge v3
`metadata.schem` carrying three supported empty-container records. It constructed
the same nine cells at `(2160..2168,300,11)`, retaining grass below the standing
sign. The operator supplied two additional plain sign items for this placement
fixture; other stock remained from the first run. After placement began, the
harness paused the project, waited for a paused worker with no pending or uncertain
pose, rebooted both computers and resumed the saved project. No pose correction
or placement intervention was needed. Final VERIFY reported nine correct cells.

Independent observer 90 world checks found all nine names/states correct, grass
intact, and all three placed container inventories empty. Furnace timers/recipe
history were empty. Sign NBT showed ordinary default empty text; the application
makes no text-verification claim. All jobs completed, no supply lease remained,
and builder 248 returned home idle with empty cargo. Stock retained 14 stone; depot
and supply were empty. Both computers were shut down and all four temporary
force-load tickets removed. The rig and both completed structures remain.

Evidence is under ignored `dist/live-placement-metadata/`, especially
`native-retest/`: input binary, paused restart snapshots, final runtime states,
independent world checks and cleanup receipts. The harness submits ordinary
controller commands at the event boundary and observes runtime state; workers
execute real turtle/peripheral/rednet APIs. It does not test synthetic keyboard
input reliability, populated containers, arbitrary metadata, sign text, player
interaction states or unrestricted modded blocks.
