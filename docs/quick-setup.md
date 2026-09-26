# Guided building setup

For release **0.10.3 or later**, follow [Start here: controller 1 and one builder](start-here.md).
It includes the hardware drawing, exact chest and fuel placement, finding
coordinates, updating the computers, and every answer needed for the first test.

The short sequence is: update controller and chosen worker with `/update.lua`
at their CraftOS prompts, then `reboot`; run `setup` **inside the running
controller app**, then inside the running worker app. Each returns to the app
automatically. On the controller, type `1` to check readiness, then `2` to start
the bundled 28-block pilot. Set up the controller before the worker. Leave the
other workers parked outside the travel route and site.

The small pilot is bundled; its menu action handles importing, preparing, and
starting it after readiness checks. The full cathedral remains a section plan
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
allows refuelling from coal or charcoal in slot 15, after settings are saved.

Normal updates preserve settings and checkpoints. Once the release is installed,
the wizard works without an internet connection; worker discovery uses the local
wireless network. GPS is optional: without it, setup asks for the turtle's block
coordinates. Setup always asks for its facing. Devices must remain loaded and in
wireless range.
