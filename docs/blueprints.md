# Importing blueprints

Run the converter on a desktop with Python 3 (no third-party packages):

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

The converter retains Minecraft DataVersion for inspection; it does not migrate
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
- `schematic.load(fs, codec, path)` reads bounded JSON and validates it. Codec must
  supply `unserializeJSON(raw)` (CC:Tweaked textutils) or `decode(raw)`.
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
python3 -m unittest discover -s tests -p 'test_*.py'
```

The converter tests create actual binary NBT fixtures for both versions and exercise
the command-line interface, malformed inputs and decompression limits. Lua tests
cover schema validation, transforms, material counts and support ordering. These are
desktop simulations; live CC:Tweaked placement must still be checked in Minecraft.
