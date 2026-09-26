# Guided building setup

Release 0.10.2 adds `setup`. It replaces editing Lua settings for the controller
and builders. It does not move turtles, dig blocks, refuel, or start a project.
Existing workers can become builders without reinstalling or changing their
installation profile. Other roles still use their documented setup procedures.

For the first cathedral test, configure **one controller and one builder**. The
other six workers can stay online, parked outside the test area and travel route.

## Place the hardware once

- Controller: wireless modem plus wired access to two chests/barrels. Enable the
  wired modems on both inventories so the controller can see their names.
- Stock chest: put **13 cobbled deepslate and 15 sandstone** here for the pilot.
- Supply chest: leave this separate chest empty. The controller will stage each
  requested material here automatically.
- Builder: pickaxe and wireless modem, parked facing the supply chest. This
  position becomes its depot. Put coal/charcoal in slot 15; reserve slot 16.
  Leave space **above the turtle** and along the travel route clear. An overhead
  chest can obstruct the builder's departure; slot 15 is enough for this small test.
- Choose an empty 8 × 8 site nearby, outside the depot, with two clear blocks above
  the target layer. Its origin is the lowest x/y/z block to place, **not** the ground
  underneath. The footprint extends east (+x) and south (+z).

GPS hosts are optional for setup: if a fix is available, the wizard uses it;
otherwise it asks for the turtle's block coordinates on one line. It always asks
for the turtle's cardinal facing. No calibration movement is attempted. Keep
devices loaded and in wireless range. Detection uses CC:Tweaked's
[peripheral API](https://tweaked.cc/module/peripheral.html) and
[GPS API](https://tweaked.cc/module/gps.html).

## Controller first

Press **Q** in Autobuilder to reach the shell. Close any other Autobuilder tabs.
Run these commands individually:

```text
update
/autobuilder/setup.lua
reboot
```

The wizard displays inventories and their contents. Select the empty supply
chest by number, select the stock chest(s), and enter the build corner as `x y z`.
Review the summary and save. It enables building and keeps site clearing off.
It preserves unrelated settings, including the controller ID and fuel reserve.
Existing imported projects retain their original import coordinates; import the
pilot after setup, or use a new project name if you previously imported it.

## Then one builder

With the controller running again, press **Q** on the chosen worker and run:

```text
update
/autobuilder/setup.lua
reboot
```

The wizard uses the worker's existing controller ID (1 in your fleet), retrieves
the supply settings from that controller, detects GPS, and asks for facing and
confirmation that the turtle is parked at its depot facing the selected chest.
It checks that a chest/barrel is in front; you must confirm it is the *same*
supply chest selected on the controller. It saves both settings and the existing
worker checkpoint's position, so already-installed workers do not need a separate
pose command. It enables the building capability and preserves other capabilities.

On a **fresh installation**, boot the worker once and wait until it appears in the
controller's Workers screen before running the wizard. Only registered workers
can retrieve the controller's setup profile. Both devices must be updated to
0.10.2 or later. If discovery times out, leave the controller running, ensure it
has completed setup, then retry on the worker.

After booting the updated program, `setup` is a short alias for
`/autobuilder/setup.lua`. The full path works immediately after updating, even
before that alias has been created. `setup builder` and `setup controller` also
work and check the installation's runtime role.

## Run the pilot

Setup automates configuration. Use the [cathedral pilot instructions](../blueprints/classic-cathedral/README.md#first-in-game-test-cathedral-detail)
to download, import, prepare and start the small test. You do not need a mining,
crafting, logging or courier station for these 28 pre-supplied blocks. Preparation
reserves materials in controller-visible storage; put the blocks in the **stock**
chest rather than preloading the supply chest.

The full cathedral remains a section plan with documented limitations; this wizard
does not add an unattended whole-cathedral dispatcher.

## Saved settings and interruptions

Setup refuses changes while local jobs, pending supply receipts, uncertain motion,
or controller production work need recovery/completion. Pausing a job does not
release ownership. Finish or recover that work first; do not delete checkpoints.

The first pre-setup settings file is preserved at
`/autobuilder/data/settings-before-setup.lua` (or under your custom `dataDir`).
New settings are validated, staged and verified using the install transaction.
If interrupted during configuration replacement, run `/installer.lua --recover`
before rebooting. A builder's confirmed current pose is saved before enabling
building; if the subsequent settings write fails, that confirmed pose can remain.
No physical movement occurred. Normal updates continue to preserve settings and
checkpoints. The wizard works offline too once the release is installed; its
worker discovery uses the local rednet network, not HTTP.
