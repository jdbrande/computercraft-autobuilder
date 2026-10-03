# 0.17.0 native schematic acceptance

Scope: bounded native gzip/NBT decoding, Sponge versions2/3 conversion, immutable
project import and `build file.schem` automatic entry. This does not finish the
remaining fleet, placement-adapter, chunk-loading or terrain-preparation scope.

## Automated evidence

- Bounded gzip: four RED→GREEN tests; full Lua496 passed.
- Typed NBT/Sponge: seven RED→GREEN tests plus independent Python converter
  comparisons; full Lua503 and18 Python tests passed.
- Import/runtime: four RED→GREEN regressions; full Lua507 and18 Python tests passed.
  Release generation/check and whitespace checks passed before review.
- Final review gate:508 Lua/18 Python tests passed; regenerated release/check and
  whitespace checks passed after the regression-backed fix below.

Coverage includes stored/fixed/dynamic compression, optional gzip headers, CRC32,
ISIZE, truncation/trailing data, expansion and cooperative-yield bounds; NBT field
kinds, dimensions, depth/nodes/lengths, duplicate keys/indices, sparse palettes,
state syntax, canonical varints, exact volume, required air, offsets, paired/slab
material counts and explicit unsupported metadata. Native and Python converters
agree across raw/gzip versions2/3 fixtures.

Import integration exposed an existing double-read bug: JSON validation and saving
could observe different source bytes. Import now uses the same snapshot for both.
Regression tests change the source immediately after closing its first read and
verify that the imported content remains the validated snapshot. Native shorthand
is idempotent across reboot and rejects changed source bytes without new work.

The bundled LibDeflate source is pinned, licensed and SHA-verified. Its marked local
extension bounds output before retained-buffer flush/final concatenation and invokes
cooperative progress. The strict wrapper validates the gzip member and trailers.

## Review correction

One Important resource issue was confirmed: consecutive stored DEFLATE blocks
appended up to65535 bytes but flushed only one32768-byte slice per block. The output
limit held, while retained history grew and caused quadratic copying. A regression
failed at622546 buffered bytes before the fix. Stored blocks now drain all full
slices with bounds/progress checks, preserving backreferences into earlier blocks.
Tests cover consecutive stored blocks and a stored-to-compressed transition.

Post-fix desktop measurements of1/4/8MiB inputs all peaked at131070 working bytes;
inflation took approximately0.066/0.257/0.512 seconds. A separate native CraftOS check
on controller130 generated128 consecutive stored blocks in memory:8,388,480 bytes
inflated in2.242 seconds with383 cooperative yields, and a1MiB bound rejected the
same stream. This isolates decoder memory/timing without exceeding the instance's
1,000,000-byte computer disk quota. No blocks were changed by this check. Its harness
was removed, controller130 shut down and test force-loading removed again.

## Native Minecraft acceptance — 2026-10-03

World `TESTINMG`, PrismLauncher Minecraft1.20.1, Forge47.4.10, CC:Tweaked1.120.0,
Advanced Peripherals0.7.48r. Controller130 and builder131 used a separate wired
supply rig around `(256..260,299..302,0..2)`. The builder started with finite2000
fuel, a diamond pickaxe, wireless modem and no building materials in its inventory.

The operator copied a real gzip Sponge v3 file to the controller and issued
`build /native_acceptance.schem`. No desktop-converted JSON was supplied. The2×1×2
volume requested two stone bricks, one glass and one required-air cell, deliberately
occupied by dirt. The controller decoded/normalized the file, prepared the existing
stock, supplied the builder, cleared the dirt, placed the three blocks and verified
all four positions. It reached `built` in approximately47.7 seconds. Independent
world commands confirmed each block and the cleared air position.

A second gzip file, `native_restart.schem`, requested16 stone bricks at
`(262..269,300,4..5)`. The harness restarted controller130 during active construction.
The original project continued without task resume/reassignment and reached `built`
in approximately133.2 seconds, reporting16 correct cells and no defects. Independent
world commands confirmed all16 blocks. Repeating `build /native_restart.schem`
reported the same completed project; job/request counts stayed7/2.

Both projects and every job completed. The builder was idle at `(269,301,5)` with
1791 finite fuel and the single dirt block recovered from clearance; central stock
and supply chests were empty. Final return/unloading is separate remaining fleet
work, not claimed by this trial. Finished materials were supplied to central stock
by the operator; this trial tests native import, supply, clearance, placement,
verification and restart, not fresh autonomous material acquisition.

The test computers were shut down and observer/rig force-load tickets removed.
The rig and19 placed blocks remain. Evidence under ignored `dist/live-schematic/`
includes compressed sources, setup commands, state stream/reboot event, both timing
results, final snapshots, repeated-command counts and independent block/NBT reads.
The harness observes normal runtime state and sends operator commands at the event
handler boundary; native turtle/peripheral/rednet APIs perform physical work.

## Limits and remaining work

Inputs/expanded bytes are bounded to32MiB, volume262144 blocks, palette65536, NBT
depth32 and one million nodes. Normalized JSON must also fit the byte limit. Native
gzip accepts one member. No Minecraft DataVersion migration is performed. The saved
offset is metadata; configured origin is the transformed volume's minimum corner.

Entities, block-entity contents and biomes produce explicit analysis issues and
prevent unattended construction. Native format support does not add placement
support for every block family. Large-scale acceptance, missing placement adapters,
automatic site leveling, dynamic role scaling, chunk loading, broader recovery,
continuous logistics and final worker settlement remain required subsequent work.
