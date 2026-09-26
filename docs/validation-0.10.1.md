# Release 0.10.1 and cathedral planning assets

The large-model simulation exposed a route bug: a low construction region could
choose a travel height below a neighboring region already built. Region jobs now
carry the project's overhead clearance, which the builder persists through movement
waits. A regression test reproduced the collision before the fix and passed afterward.

Validation:

- 253 Lua tests pass, including the new clearance regression with checkpoint
  reconstruction on every movement tick.
- 13 Python tests pass, including cathedral mapping, run encoding, section offsets,
  source preservation, checksums and refusal to overwrite existing output.
- All 299 generated cathedral sections pass volume, palette, run length, material,
  byte length and SHA-256 checks. They contain 770,617 planned non-air blocks.
- The actual `cathedral-pilot.json` passed import, analysis, simulation, preparation,
  building, automatic verification and an additional explicit verification in the
  controller/worker runtime fixture. Controller and worker restarted after the first
  placement. Exactly 28 blocks were placed, zero blocks dug, and all 64 cells verified
  correctly. All six jobs completed without duplicate placements.

The pilot fixture supplied inventory and unlimited turtle fuel; separate existing
tests cover resupply and fuel logic. This is not a live Minecraft result, a full
cathedral construction simulation, or evidence that covered cells can be inspected.
The complete source exceeds the runtime's volume and practical project-history
limits. Section orchestration, archival and inspection access remain necessary
before whole-cathedral unattended construction.

See the [cathedral guide](../blueprints/classic-cathedral/README.md) for the original
versus simplified counts, documented omissions, material totals and live pilot steps.
