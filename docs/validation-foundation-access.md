# Automatic foundation access acceptance — 2026-10-03

Intermediate 0.23 evidence, using controller206 and builder207 in the existing
Minecraft1.20.1/Forge47.4.10/CC:Tweaked1.120.0/Advanced Peripherals0.7.48r instance,
world`TESTINMG`. The worker had a pickaxe, wireless modem,16,000 finite fuel and
no Geo Scanner. Four chunks were operator force-loaded.

The schematic requested nine stone floor blocks at`(952..954,300,6..8)`, already
present. Two layers of ground covered`(951..955,298..299,5..9)`, with the support
at`(953,299,7)` deliberately absent. Adjacent stone and the retained floor sealed
that missing support from ordinary inspection. Central storage contained32 stone
and32 cobblestone; the builder had private supply and return chests.

`build auto hidden` surveyed the site, opened temporary shafts and tunnels,
inspected and filled the missing support, and restored excavated ground before
certifying preparation. The final project reached`built` with **9 correct** blocks
and no defects. All122 jobs completed, including91 access child jobs. The builder
returned idle to`(944,301,0)`, facing north, with11,868 fuel and empty cargo; no
active supply lease remained.

Independent world commands checked100 coordinates:25 lower ground cells,25 upper
support cells, all nine retained stone floor blocks and41 required air cells.
All checks passed. The missing center support was cobblestone. Central stock
retained32 stone and31 cobblestone, and both private chests were empty. Thus the
trial consumed one net support block while retaining the requested floor and
restoring the temporary ground access.

A controller restart during debris return preserved the work. The project was
also paused and the worker restarted idle at the shaft entrance, with unchanged
position and heading, then resumed. This does not establish recovery from a
power loss during an ambiguous physical movement. A later controller-only update
installed the preparation settlement gate and restarted the controller.

Both computers were shut down and all four test force-load tickets removed.
The rig and completed floor remain for inspection. No world backup was made and
the harness did not move the player. Automatic pause on focus loss remained
disabled for the separate cross-region and external-inflow trials still running
at the time this report was written.

Ignored`dist/live-foundation-access/` contains setup commands, deployed source
hashes, sampled runtime state, restart records, final checkpoints, independent
block/inventory observations and cleanup receipts. Commands entered the normal
controller event-handler boundary; this is not terminal-input acceptance.

This small trial uses one preparation region and known loaded terrain. Cross-region
access, concurrent fleets, automatic loading and large-scale throughput require
their separate acceptance evidence. The bounded implementation currently performs
many small access jobs even for existing sealed supports; this trial records that
cost rather than claiming efficient large-foundation throughput.

## Cross-region access

A second rig used controller208 and builder209 with the same3×3 retained floor
and sealed center hole, shifted32 blocks east. Setting`regionSize=2` divided the
working area into nine preparation regions. The interior region could reach its
hidden supports only through the project margin and neighboring regions. Sampled
native state recorded38 child jobs with explicit cross-region access bounds.

All nine preparation regions completed, then final verification reported **9
correct** floor blocks. All120 jobs completed. The temporary access lease and
supply lease were released, and the worker returned idle and empty to
`(976,301,0)`, facing north, with12,470 of its initial16,000 fuel remaining.
The controller restarted after the settlement-gate update and again after the
review fixes, preserving active preparation and physical ownership.

Independent commands checked100 coordinates at`(983..987,298..301,5..9)`:
all50 required ground/support cells, nine retained floor blocks and41 air cells
matched. The missing center`(985,299,7)` was cobblestone. Central stock contained
32 stone and31 cobblestone; private return and supply chests were empty.
Both computers were shut down and all four force-load tickets removed. The
floor and rig remain in place. Local setup, sampled cross-region routes, deployed
update hashes, final state, independent observations and cleanup receipts are in
ignored`dist/live-cross-access/`. Focus-loss pause remained disabled for the
separate external-inflow trial.

This establishes native execution of cross-region temporary access and restoration
with a single worker. Shared-lease concurrency and corruption recovery retain
simulation coverage; this trial did not inject sidecar corruption or ambiguous
worker movement interruption.
