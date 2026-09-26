# Classic cathedral: simplified section plan

The supplied `classic-cathedral.schem` has been preserved locally. This folder
contains an explicitly simplified approximation for testing and further planning.
**Only the small pilot below is the initial in-game test target. The 299 full
sections are not an unattended whole-cathedral build.**

| Measurement | Original | Simplified plan |
| --- | ---: | ---: |
| Bounding dimensions, X × Y × Z | 416 × 256 × 239 | 416 × 256 × 239 |
| Non-air cells | 2,881,236 | 770,617 |
| Omitted cells | — | 2,110,619 |
| Non-empty 32 × 32 × 32 sections | — | 299 |
| Placement materials | Hundreds of block types/states | 8 full-block materials |

The original contains 2,542 block entities and 438 entities; none is reproduced.
`catalog.json` records every section's original local offset, dimensions, block
count, material requirements, byte size and SHA-256. `substitutions.json` lists all
source-to-output changes and counts. `materials.csv` is the complete bill of materials.

## What changed

- Dirt, grass terrain, bedrock, gravel, sand, and natural stone below original local
  Y=32 are removed. This is a material-based approximation, not a semantic extraction
  of the building: buried stone foundations can also be omitted. A prepared build
  site and any desired replacement foundations remain separate work.
- Quartz and pale masonry become polished diorite. Dark roofs/masonry become
  cobbled deepslate. Other masonry becomes stone bricks, bricks or sandstone.
- Timber becomes oak or spruce planks; logs lose axis and bark appearance.
- Stairs, slabs and many walls become full blocks at the same coordinates. Roofs,
  arches and trim become coarser, and staircases may need manual finishing for access.
- Glass, glass panes, railings and fences become clear full glass blocks.
- Interactive fixtures, unsupported decoration, vegetation, furniture, fluid,
  redstone and special helper blocks are omitted. There is no restored sign text,
  inventory contents, banner design, functional machinery or entity data.
- The lighting design is not retained. Light-emitting decorations are omitted or
  replaced with ordinary materials; add functional lighting separately.

All output block states are empty because this profile uses only nondirectional
full cubes. The source NBT warnings are retained as provenance, while the simplified
model explicitly requests none of those omitted features. This is not a faithful
restoration of the original cathedral.

## First in-game test: cathedral detail

`cathedral-pilot.json` is an **8 × 1 × 8** exposed detail taken from original local
coordinates **(0,26,0)**. It contains **28 blocks**: 13 cobbled deepslate and
15 sandstone; the other 36 cells are air. It is a small decorative ground/detail
sample, not a miniature of the whole cathedral.

1. Update to release **0.10.4 or later** and follow [Start here](../../docs/start-here.md).
   On the controller and chosen builder, press **Q**, run **`/update.lua`**, then
   **`reboot`**. Run controller `setup` first and press **Enter** or type **`auto`**
   at **Build corner**. Run the chosen worker's `setup` to save its actual turtle
   coordinates and heading; GPS is optional. The other six can stay idle outside
   the work area.
2. Put **13 cobbled deepslate and 15 sandstone in STOCK**, keep SUPPLY empty, and
   put **16 coal/charcoal or 2 coal blocks in turtle slot 15**. The wizard consumes
   only enough to reach **1,000 fuel**; two coal blocks provide 1,600 from empty
   with default fuel values.
3. On the running controller, type **`1`** and press Enter. Fix any missing setup
   item, then type **`2`** and press Enter. This imports the bundled pilot,
   clears its automatic site, prepares the supplied blocks, builds, and verifies it.
   No separate blueprint download or import/prepare/start commands are needed.
4. Keep other workers and players away. `3` pauses clearing or building and `4`
   continues the saved test. `5` shows workers; `6` shows jobs.

AUTO starts the **8 × 8** footprint **two blocks behind** the builder parked with
its front against the supply chest, at the turtle's height. It clears the bottom
layer and two layers above, an **8 × 10 overhead rectangle** over the
depot-to-footprint route, and the depot shaft. Ground below stays and bounds do
not expand. Only common natural terrain is removed; containers, machines, ores,
liquids, waterlogged blocks and protected blocks/areas stop clearing. Drops remain
in slots **1–14**. For an ordinary inventory-full stop, pause, empty cargo and
resume. **Do not alter inventory or the target block when an unresolved dig or
ambiguous outcome needs recovery.**

To use a manual site instead, enter its northwest build-bottom corner as `x y z`
in controller setup. Prepare that 8 × 8 patch, two empty layers above it and the
route yourself; manual mode does not use automatic site clearing.

Success is **28 physical placements and 64 correct verification cells**, with no
wrong, missing, unsupported or inaccessible cells. The project is named
`first_cathedral_test`; repeating `2` will not build a second copy. This mode waits
for missing stock to be supplied manually rather than starting mining/crafting.

After a successful run, test a controller/worker reboot. For an advanced repair
trial on one removed, exposed block, use `build repair first_cathedral_test`.
Record real fuel usage, elapsed time, supply behavior and filesystem growth before
scaling up. `cathedral-pilot.json` remains available for advanced/manual imports.
No live Minecraft acceptance run has been performed; the automated checks use
simulated hardware.

## Full-section limitations

The current runtime has no cathedral section dispatcher, automatic mobile depot,
completed-project archive or persistent-memory cleanup for hundreds of projects.
Do not import/analyze all 299 sections together. Expanded blueprint caches and
retained jobs can exhaust computer memory/filesystem capacity. Source files alone
are about 14 MB, so copying the whole catalog into a standard computer is inappropriate.

The verifier currently inspects a full cube from the position immediately above
it. After walls, floors or solid masses cover that position, a section can report
`inaccessible` even when a turtle previously placed those blocks. Splitting the
volume does not fix inspection access. Section scheduling and verification access
need more work before an unattended full cathedral build is supported.

The catalog's order is increasing source Y, then Z, then X. For any future section
trial at zero rotation and no mirrors:

```text
section world origin = chosen cathedral base origin + catalog section offset
```

Set that exact `build.origin` **before importing** the section: imports snapshot the
transform, and metadata offsets do not position it automatically. Rotation/mirroring
must be applied to the complete cathedral layout, not independently to section files.

The 416×239 footprint needs staged local depots or an improved transport system;
raising the 256-block travel limit alone does not create clear routes or supply fuel.
Move/reconfigure a depot only after its tasks, motion and supply journals are resolved.

The retained volume is 256 blocks tall. With the current overhead travel strategy,
a standard Overworld base origin Y=64 would request clearance above the world's
upper boundary. A full-height layout needs base Y≤62 and lower-bound checking, or
a deliberately revised layout; a practical lower base gives more overhead margin.
Modern Overworld height bounds originate in the official
[Caves & Cliffs height expansion](https://www.minecraft.net/pl-pl/article/caves---cliffs-part-ii-the-features).
This height constraint does not apply to the one-layer pilot in the same way.

## Reproduce the planning assets

The original `.schem` is not published here. With your supplied file locally:

```sh
python3 tools/prepare_cathedral.py classic-cathedral.schem /new/output/directory
```

The desktop-only tool accepts up to 32,000,000 source cells under the converter's
32 MiB byte limits. It does not increase the runtime's 262,144-cell limit. Every
export section stays at or below 32,768 cells. Existing output directories are
refused. Provenance and the source SHA-256 are recorded in the catalog.
