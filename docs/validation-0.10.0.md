# Release 0.10.0 validation

Verified on 2026-09-26 with the desktop Lua 5.2 simulation and Python test suite:

- 252 Lua tests passed: controller/worker lifecycle, mining, resource planning,
  crafting, parallel furnace banks, schematic transforms, construction, full-volume
  verification/repair, managed farms, courier/resupply, concurrent ownership,
  movement reservations, interruption recovery, installer/update and depot footprint.
- 9 Python tests passed: bounded Sponge v2/v3 conversion, malformed input,
  manifest hashes, role dependencies, all offline profiles and standalone bootstrap.
- `python3 tools/release.py --check` verified generated installer/manifest agreement.
- Independent integration review found no remaining critical regressions after
  the movement, door verification, inventory coordination and farm-supply fixes.

The runtime tests model inventory contents, changing world blocks and furnace
processing; they do not replace testing on Minecraft's actual turtle placement,
peripheral, chunk-loading and server-protection behavior. No live Minecraft run
was available in the development workspace.

The release provides a bounded implementation. Placement support is explicit in
[construction](construction.md); managed renewables require prepared farms, and
[depot expansion](infrastructure.md) builds a configured footprint without wiring
or registering new storage. Inaccessible cells and unsupported operations remain
visible instead of being counted as successful work. Start with a small disposable
test site and the setup instructions in the README.

Offline worker profiles use example controller ID **7**. Set the actual ID,
coordinates, heading, depot and peripheral names in `autobuilder/settings.lua`
before starting. The GitHub installation asks for that ID or accepts it as an argument.
