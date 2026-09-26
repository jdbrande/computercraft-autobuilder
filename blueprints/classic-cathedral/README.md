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

1. Use release 0.10.2 or later. Follow [guided setup](../../docs/quick-setup.md)
   on the controller and **one builder**; no Lua settings edits are needed.
2. The controller wizard asks for the minimum corner of a clear 8×8 test area
   and selects the stock and supply chests. It enables building, sets rotation 0,
   disables mirrors and keeps `clearSite=false`.
3. The builder wizard retrieves supply settings and saves its position, facing
   and depot. Leave two clear blocks above all 64 target cells, plus an unobstructed
   route to the depot outside the footprint. Keep the other workers out of the way.
4. Stock the source chest with 13 cobbled deepslate and 15 sandstone. Fuel the
   builder separately with coal/charcoal in slot 15. Leave the supply chest empty.
5. At the controller's CraftOS shell, download the pilot:

   ```text
   wget https://raw.githubusercontent.com/jdbrande/computercraft-autobuilder/main/blueprints/classic-cathedral/cathedral-pilot.json /cathedral-pilot.json
   ```

   `wget` refuses an existing file. Preserve or rename an old copy explicitly if
   needed. Start `/autobuilder/startup.lua` after changing the settings.
6. In the running controller, enter:

   ```text
   build import /cathedral-pilot.json cathedral_pilot
   build analyze cathedral_pilot
   build simulate cathedral_pilot
   build prepare cathedral_pilot
   ```

   Wait for the project to become `ready`, then:

   ```text
   build start cathedral_pilot
   build status cathedral_pilot
   ```

   The successful result is `built`, 28 physical placements and **64 correct
   verification cells**, with no wrong, missing, unsupported or inaccessible cells.
   If it blocks, preserve the job/checkpoint and inspect `jobs` and `errors`.
7. After a successful run, test a controller/worker reboot and repair one removed,
   exposed block using `build repair cathedral_pilot`. Record real fuel usage,
   elapsed time, supply behavior and filesystem growth before scaling up.

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
