# Remaining deterministic placement adapters

Requirements6 and19–20 extend the current finite block classification, placement
plans, support graph and builder journals. Keep unsupported states explicit. Reuse
the builder's inspection, intent, traffic and final verification paths; do not add a
parallel placement engine.

Add ordinary beds as paired foot/head placements using one item. Generalize paired
inspection geometry and generated-cell ownership, retaining the existing door hinge
checks only for doors. Both bed floors and both generated cells require permission
and support. Head entries are observation-only. Cross-region head dependencies must
reference their foot, and supply/material accounting must count one bed.

Add floor/wall/ceiling buttons and levers in supported unpowered states; ordinary
straight flat rails and unpowered powered/detector/activator rails; unpowered
redstone wire/torches and basic repeaters/comparators where deterministic native
placement can establish the requested state. Native trials decide exact facing
behavior. Unsupported delay/mode/curve/slope or powered conditions must remain
explicit until a tested interaction adapter exists. Wire/rail neighborhood-derived
states require final verification after neighboring placements, as panes/fences do.

Add simple plants with validated substrates: flowers and saplings on supported
soil, plus crop seedlings on farmland where native placement is deterministic.
Never treat arbitrary modded blocks as cubes. Placement support checks distinguish
solid attachment faces from plant substrates. Required support dependencies must
cross region boundaries and retained prepared regions must remain protected.

Analyzer output should explicitly identify attached/gravity/paired/redstone/fluid
families, special placement/tool requirements and unsupported metadata. Supported
block-entity payloads, sign text and controlled fluid placements follow this adapter
foundation in the next milestone; raw NBT is never silently discarded.

Tests cover transforms, material aliases, dependency ordering, paired footprints,
actual builder recovery after side effects, final-state verification and missing
supports. Native acceptance checks a compact mixed adapter structure independently,
including controller/worker restart where useful. One final review/consolidated
fix pass, full gates and permanent evidence precede ordered integration.
