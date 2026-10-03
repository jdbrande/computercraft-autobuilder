# Native Sponge schematic import

Requirements6 and33 need a controller-side `.schem` entry point. Existing compact
JSON analysis, material planning, transforms, protection and project checkpoints
remain the canonical execution path. Decode the whole source before creating any
project or physical work. Support Sponge versions2 and3, raw or gzip NBT.

## Format and bounds

- Retain the current32MiB source/expanded limit,262144-block volume limit and65536
  palette limit. NBT parsing limits depth32 and total nodes1000000, rejects negative
  lengths, duplicate compound keys, unknown tag types and trailing bytes.
- Read files in binary mode. Gzip validates headers, optional fields/header CRC,
  DEFLATE termination, data CRC32 and ISIZE. Reject concatenated members/trailing
  data; Sponge files contain one NBT document. Bound output during inflation,
  before concatenation, and yield during long CPU loops on CraftOS.
- Vendor pinned dependency-free LibDeflate under its zlib license. Its tested
  DEFLATE implementation is preferable to a new compressor/parser. Mark a small
  local bounded-output/cooperative-progress extension and retain upstream source,
  license and provenance. No network fetch is required at runtime.
- Keep NBT tag kinds to reject wrong types in dimensions, versions, palettes,
  offsets and block arrays. Width/height/length are unsigned interpretations of
  TAG_Short. Ignore unused metadata values after bounded parsing; never execute
  embedded data. Reject malformed block-state properties and noncanonical,
  overflowing, unknown or wrong-volume palette varints.

## Conversion and commands

Convert to existing schema1: sorted/remapped palette, run-length block data,
source/data versions, schematic offset and explicit unsupported metadata issues.
Recompute material quantities with the existing blueprint implementation (paired
blocks, aliases and double slabs). Preserve every air cell. Offset is retained as
source metadata; configured project origin continues to identify the minimum
corner of the transformed volume, matching desktop imports.

`build import file.schem [name]` stores a validated immutable JSON copy with the
existing hash and protection contract. `build file.schem` imports and requests the
normal automatic project pipeline using configured origin. A repeated shorthand
must not duplicate an active project or replace a changed source. Existing JSON
commands remain compatible. Report unsupported entities/block entities/biomes
through analysis and refuse unattended construction until supported; parser
support does not claim block/entity restoration support.

## Evidence and risks

Tests compare native output with standard-library Python converter fixtures for
both versions, including palettes/states/air/offsets and unsupported metadata.
Exercise stored/fixed/dynamic DEFLATE, malformed headers, corrupt checksums,
truncation, output/depth/node limits, bad tags and varints. Reboot/import hash and
invalid-source tests prove no jobs are issued before successful analysis.
Native acceptance imports a gzip `.schem`, constructs/verifies a small supported
structure and independently reads resulting world blocks. Keep broader placement
adapters, continuous pipeline, chunk loading, dynamic scaling and full terrain
preparation as required subsequent work in the progress ledger.

Sources: [Sponge v3 specification](https://github.com/SpongePowered/Schematic-Specification/blob/master/versions/schematic-3.md),
[CC binary filesystem API](https://tweaked.cc/module/fs.html),
[LibDeflate](https://github.com/SafeteeWoW/LibDeflate), pinned commit
`afc3b78d12fb3bcfa6b21e5332031ad3d7572e19`.
