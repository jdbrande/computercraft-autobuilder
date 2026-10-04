# Supported container and sign schematic data

Requirements6 and19–20 require supported block-entity data, attached signs and
block-specific placement. Extend the existing finite placement and native Sponge
import paths. Unsupported states and payloads must remain explicit analyzer issues.

Add ordinary single chests, barrels and unlit empty furnaces with deterministic
horizontal facing, plus standing/wall signs at the cardinal rotations supported by
a turtle. Use native probes to establish placement orientation and the observations
available through adjacent peripherals. Do not infer restored contents or sign text
from a successful block placement.

Normalize only bounded, supported empty block-entity payloads during import. Retain
coordinates and validate their matching palette blocks. Reject nonempty inventory,
loot tables, custom names, locks, active burn/cook state, unsupported sign styling or
text and arbitrary modded NBT unless there is a real read/verify adapter. Read-only
verification must use the same metadata contract during recovery and final project
verification. The existing rule permitting unsupported blocks with clear errors is
part of the fleet requirements; arbitrary NBT restoration is not claimed.

Sign text is a native placement parameter, but ordinary turtle inspection returns
block names/states rather than sign contents. A metadata feature is supported only
when available hardware can also verify its result after restart. This distinction
must be visible in analysis and documentation.

Reuse placement journals, paired/chunk protection, support dependencies, item aliases,
measured supply and final reports. Do not introduce a second schematic representation
or independent placement scheduler. Tests cover binary v2/v3 input, malformed and
nonempty payload rejection, aliases, transforms, native facing, interrupted placement,
read-only contents verification and protected neighboring containers. Run one final
whole-branch review/consolidated correction pass, full gates and native acceptance
before ordered integration. Continue remaining rescue, scheduling, dashboard/logging
and larger fleet acceptance afterward.

Reference: [CC:Tweaked turtle API](https://tweaked.cc/module/turtle.html) documents
sign text in placement and the name/state observation contract; native probes are
required for the installed1.20.1 environment.
