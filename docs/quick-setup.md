# Guided building setup

For release **0.10.4 or later**, follow [Start here: controller 1 and one builder](start-here.md).
It includes the hardware drawing, exact chest and fuel placement, finding
coordinates, updating the computers, and every answer needed for the first test.

The short sequence is: press **Q** to leave Autobuilder, then update controller
and chosen worker with `/update.lua` at their CraftOS prompts, then `reboot`;
run `setup` **inside the running
controller app**, then inside the running worker app. Each returns to the app
automatically. At the controller's **Build corner** prompt, press **Enter** or
type **`auto`**. The worker still needs its actual saved turtle coordinates and
heading; GPS is optional. Load **16 coal/charcoal or 2 coal blocks in slot 15**;
setup consumes only enough to reach at least **1,000 fuel** (two coal blocks
supply 1,600 from empty with default fuel values). On the controller, type `1`
to check readiness, then `2` to clear and build the bundled 28-block pilot.
Set up the controller before the worker. Leave the other six workers and players
outside the travel route and site. `3` pauses clearing or building; `4` resumes it.

AUTO selects an **8 × 8** footprint beginning **two blocks behind** the builder
parked facing its supply chest, at the turtle's height. It clears the build layer
and two layers above, an **8 × 10 overhead rectangle** over the depot-to-footprint
route, and the depot shaft. Ground below stays; the bounds never expand. Only
common natural terrain is accepted: containers, machines, ores, liquids,
waterlogged blocks and protected areas stop clearing. Drops stay in slots **1–14**.
An ordinary inventory-full stop can be resolved by pausing and emptying cargo,
then resuming. **Do not change inventory or the target block if an unresolved dig
or ambiguous outcome needs recovery.**

For a manual site, enter its northwest build-bottom corner as **`x y z`** instead
of `auto`, and prepare the 8 × 8 area, two layers above and route yourself.

The small pilot is bundled; its menu action handles importing, site clearing,
preparing, and starting it after readiness checks. The full cathedral remains a section plan
with limitations, not an unattended whole-cathedral dispatcher.

## Saved settings and interruptions

Setup refuses changes while local jobs, pending supply receipts, uncertain
motion, or controller production work need recovery or completion. Pausing a
job does not release ownership. Finish or recover that work first; do not delete
checkpoints.

The first pre-setup settings file is preserved at
`/autobuilder/data/settings-before-setup.lua` (or under your custom `dataDir`).
New settings are validated, staged, and verified using the install transaction.
If interrupted during configuration replacement, run `/installer.lua --recover`
at the affected computer's CraftOS prompt before rebooting. A builder's confirmed
current position and facing are saved before enabling building; if the settings
write subsequently fails, that confirmed position can remain. Setup itself
performs no physical movement. On a builder, the final save confirmation also
allows refuelling from coal, charcoal or coal blocks in slot 15, after settings are saved.

Normal updates preserve settings and checkpoints. Once the release is installed,
the wizard works without an internet connection; worker discovery uses the local
wireless network. GPS is optional: without it, setup asks for the turtle's block
coordinates. Setup always asks for its facing. Devices must remain loaded and in
wireless range.
