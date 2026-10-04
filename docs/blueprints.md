# Importing blueprints

Copy a Sponge v2/v3 `.schem` to the controller. With `build.enabled=true` and the
origin configured, run `build /house.schem` to import and start automatic material
preparation/construction. To inspect first, use `build import /house.schem house`,
`build analyze house`, then `build auto house`. Repeating the shorthand preserves
the same project across restarts; changed source bytes or an existing unrelated
name require `build import /house.schem new_name`.

On the0.23 development branch, `build survey house` performs a read-only survey of
the transformed footprint and working margin. It inspects columns from overhead,
records the first surface or the configured lower boundary, and preserves exact
blocked coordinates. Hidden cells below the first solid surface remain unknown.
`build pause house` and `build resume house` control this work. Blocked overhead
access produces a new immutable attempt eight blocks higher, up to the dimension
ceiling. `surveyed` means observations were collected; it does not mean terrain has
been leveled or construction is safe to start.

Configure `build.site.minY`, `build.site.maxY` and `build.site.margin` before import
(defaults-64,319 and1). These settings and `build.regionSize` are captured with the
project. At most four survey payloads are pending at once. Bounded region evidence
is checkpointed under `<dataDir>/sites/<project>/<geometry identity>/<generation>/`;
missing or corrupt evidence cannot certify preparation.

`build level house` runs survey followed by bounded excavation, foundation fill,
and preparation verification. It preserves matching schematic cells and required
air, including intentional stepped foundations. Debris returns use the worker's
registered private home buffer and central storage before the region continues.
Fill prefers available common stable terrain materials, accounting for reservations;
missing stock follows the ordinary production/supply path. Existing suitable ground
is retained. Each region must pass foundation and clearance verification before it
is reported prepared; failures retain coordinates, observed blocks and reasons.
Independent regions continue when another has a defect.

On the0.23 development branch, normal `build auto`, `build start` and `build repair`
run this preparation pipeline automatically. Structural work waits for verified
preparation in its region and adjacent access columns; an independent region can
build while another remains blocked. Repairs resurvey changed terrain. Air-only
schematics clear the requested volume without adding an implicit foundation.
`build level` stops at `site_ready` without placing the structural schematic.

Lost region evidence reopens surveying and verification while retaining physical
owners and cargo settlement. Retiring streamed projects removes their region files
only after the controller backup no longer references the project. Construction, repair and mining now request controller permission before mutation;
generated door halves share one atomic grant. Flowing-fluid clearance, protection
for the remaining legacy/renewable executors and
native uneven-terrain acceptance remain in progress; requirement45 is not complete.

Import reads one binary snapshot, validates the whole structure, and saves an
immutable JSON copy. Corrupt data creates no project; unsupported entities or
block metadata remain analyzable but prevent automatic physical work. Native gzip
supports one member and rejects trailing/concatenated members, corrupt headers,
CRC32 and size mismatches. Expansion is bounded while decoding and yields on
CraftOS. It bundles licensed [LibDeflate](../autobuilder/vendor/README.md).

The desktop converter remains available with Python3 (no third-party packages):

```sh
python3 tools/schem_converter.py house.schem house.json
```

Copy the resulting JSON to the controller before importing it. The converter refuses
an existing output path. Malformed data exits with a nonzero status and a diagnostic;
conversion completes before the output file is opened. The generated examples are
`examples/stone-foundation.json` (six stone bricks) and `examples/log-corner.json`
(two horizontal logs and two air cells).

The binary reader accepts gzip and raw big-endian NBT for Sponge versions 2 and 3.
Version 3 uses its nested Schematic/Blocks container. Palette indices become
one-based JSON IDs. The volume order is x first, then z, then y. References:
[Sponge v2 specification](https://github.com/SpongePowered/Schematic-Specification/blob/master/versions/schematic-2.md)
and [Sponge v3 specification](https://github.com/SpongePowered/Schematic-Specification/blob/master/versions/schematic-3.md).

Limits are 32 MiB compressed/uncompressed input, 262,144 blocks, 65,536 palette
entries, 32 nested NBT levels and one million decoded tags. Invalid lengths,
truncation, duplicate compound keys/indices, invalid block properties, unknown
palette references, overlong varints and trailing NBT data are rejected. The parser
requires a local palette; legacy numeric block registries are not supported.

Both import paths retain Minecraft DataVersion for inspection; they do not migrate
block names between game versions. Entity, block entity NBT and biome restoration
are unsupported. Their presence produces explicit strings in `metadata.issues`.
This includes sign text, inventories and other per-position NBT. These issues must
remain visible during project analysis; a controller must not claim they were built.
Source offsets are retained in `metadata.offset` but are not automatically applied:
the requested build origin is the minimum corner of the transformed volume.

## Compact schema

```json
{"schema":1,"size":{"x":2,"y":1,"z":1},"palette":[{"name":"minecraft:stone","state":{}}],"runs":[{"id":1,"count":2}],"metadata":{},"requirements":{"minecraft:stone":2}}
```

Every run has a positive count and a valid palette ID. Runs must exactly fill the
volume, including air. Block properties are strings. The supplied requirements are
informational: Lua recomputes material counts from the actual runs. It excludes air,
counts the lower half of doors and foot of beds once, and counts double slabs twice.
Wall torches and redstone wire map to their item names. Pair counts assume complete
pairs; counts do not prove that paired or other special blocks can be placed.
Unsupported acquisition and placement families must be reported by the planner.

## Lua API

- `schematic.validate(data)` returns `data` or `nil, error`.
- `schematic.load(fs, codec, path)` reads bounded binary bytes, decodes `.schem`
  through the native Sponge parser or validates JSON, and returns `data, error,
  sourceBytes`. JSON needs `unserializeJSON(raw)` or `decode(raw)`; native project
  normalization needs `serializeJSON(data)` (CC:Tweaked textutils).
- `sponge.decode(bytes)` returns validated schema1 or raises a format diagnostic.
- `nbt.decode(bytes)` returns typed nodes. Unused long/float/double values and long
  arrays remain exact raw bytes; numeric schematic fields retain their tag kinds.
- `blueprint.blocks(data, origin, rotation, mirrorX, mirrorZ)` returns a dense array
  of absolute `{x,y,z,name,state}` records, skipping all air variants. It asserts on
  invalid input. The default origin is zero and default rotation is zero.
- `blueprint.quantities(data)` returns a map from item name to required count.
- `blueprint.regions(blocks, size)` returns dependency-ordered regions. Size defaults
  to 8 and can be an integer or `{x,y,z}`. Each region has `id`, `blocks`, actual
  `min`/`max` bounds, and `dependencies` listing prerequisite region IDs. IDs encode
  the stable absolute grid coordinate as `x,y,z`.
- `transforms.position(pos, size, rotation, mirrorX, mirrorZ)` transforms a relative
  coordinate into a nonnegative rotated bounding volume.
- `transforms.state(state, rotation, mirrorX, mirrorZ)` returns a copied state map.

Mirroring occurs before rotation. Positive 90-degree rotation turns north to east.
Only 0/90/180/270 are accepted. Facing, horizontal axis, connection direction keys,
rail shapes, standing rotation (0–15), stair handedness, door hinges and paired
chest handedness transform together. Unknown properties are preserved; preservation
is not a promise that a modded property has been geometrically transformed.

Regions order existing lower supports before higher cells and wall supports before
attachments. Beds include foot-before-head dependencies; ceiling attachments depend
on the block above. Missing supports in the blueprint must be inspected in the world
by the builder. Dependency cycles are rejected, including cycles introduced by coarse
partitioning; use smaller regions or correct the structure. Ordering alone does not
prove turtle access, supported placement, or that a region can safely be built.

## Verification

```sh
.venv/bin/python tests/run.py
.venv/bin/python -m unittest discover -s tests -p 'test_*.py'
```

The converter tests create actual binary NBT fixtures for both versions and exercise
the command-line interface, malformed inputs and decompression limits. Lua tests
cover schema validation, transforms, material counts and support ordering. These are
desktop simulations. Native import/placement evidence is recorded separately in
[0.17 acceptance](validation-0.17.0.md).

Final verification after construction now starts up to three automatic repair
rounds, each with a fresh preparation survey. Correct blocks are retained. Repeated
defects stop with an exact report and retry-limit explanation. `build verify`
remains read-only; `build repair` explicitly starts a fresh repair budget.

## Deterministic attached, paired and redstone adapters

Beds require both explicit foot/head entries, matching facing and unoccupied state.
They consume one bed item. The foot waits for both floors; the builder journals and
verifies both generated cells. Missing or contradictory paired schematic entries
are analyzer errors, including door halves. Head/upper entries never consume a
second item in supply forecasts or material reports.

Buttons and levers support floor, wall and ceiling placement when unpowered. Rails
support dry straight flat shapes; powered/detector/activator rails must be unpowered.
Repeaters support delay1, unlocked, unpowered; comparators support compare mode,
unpowered. Redstone torches support lit states with explicit wall facing where
applicable. Wire requires power0 and explicit connection states. Neighborhood-derived
states are verified after placement and again by whole-project verification. Sloped
or curved rails, powered circuits and interaction-configured settings remain explicit
unsupported states pending their interaction adapters.

Ordinary small flowers, listed vanilla saplings at stage0 and wheat/carrot/potato/
beetroot seedlings at age0 have native placement adapters. Native item placement
validates soil without putting a solid turtle on farmland. Supplying an existing
plantable substrate is required; creating/maintaining farmland and mature growth
states is a separate substrate/tool operation. Site preparation must not be treated
as evidence that arbitrary soil is already plantable. Growth after placement may
change the exact state before verification.

`build analyze` saves `placementFamilies` and per-palette `placementStrategies` in
project analysis, alongside resource planning and exact unsupported reasons. Fluids,
unknown blocks and special acquisition blocks remain visible even without a placement
adapter; metadata is never silently treated as supported.

Bed-containing schematics use one-block-high construction regions so a foot can
wait for the floor across a horizontal tile boundary without cycling through the
head region. Generated cells are included in ownership and chunk coverage. New
adapters and crop preparation require `placementV1`; existing owners retain their
recovery path. Destructive repair of doors and beds is refused because removing one
half can affect the other. Both halves must be handled by a future paired removal
contract before automatic destructive repair can be enabled.

Existing farmland beneath a seedling footprint is retained as an explicit read-only
substrate requirement. Surveys stop above its empty crop cell and record the soil as
unobserved; preparation then inspects it from a side or beneath using the existing
access recovery path. Farmland is never classified as a general solid support and
missing soil is not replaced with fill. This supports supplied farmland without
claiming automatic creation of farmland.
