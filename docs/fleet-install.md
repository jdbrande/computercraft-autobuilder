# One-command fleet enrollment

On a fresh turtle with a wireless modem, run:

```text
wget run https://raw.githubusercontent.com/jdbrande/computercraft-autobuilder/main/fleet.lua install
```

Once installed, use `fleet install` from the computer root, or `/fleet.lua install`
from anywhere. Press Q to leave Autobuilder before installing/updating. The command
finds one enabled controller, verifies/downloads its current release through the
existing installer transaction, receives configuration and reboots into ordinary
registration with hardware/software health. It never moves or refuels the turtle.

The controller must already run this release and opt into enrollment in settings:

```lua
fleet = {
  enabled = true,
  profiles = {
    {workerId=12, settings={
      initialPosition={x=12,y=64,z=-9,heading='east'},
      depot={x=12,y=64,z=-9},
      automation={building=true},
      supply={inventory='minecraft:chest_2',side='front',batch=64},
    }},
  },
},
```

Use real station coordinates and inventory names. Supply, home return buffers,
mining exits and factory infrastructure still need their ordinary controller
configuration. Roles remain explicit; installed hardware determines eligibility.
Omit `workerId` to match a berth by GPS position. Place the turtle facing the
configured heading. GPS provides position, not heading, and enrollment does not
move it to infer orientation. An ID profile can enroll without GPS; conflicting
GPS evidence is refused. Each configured berth is unique.

Without a matching profile the turtle still installs and registers telemetry,
while physical roles remain disabled. Add its profile or use ordinary guided setup.
Profiles cannot replace local data/log paths, change controller identity, discard
owned tasks or bypass uncertain movement recovery.

If multiple controllers reply, select one explicitly:

```text
fleet install --controller 7
```

If discovery reaches its packet limit before the discovery window ends, unpinned
installation stops with a retry/explicit-controller message. It does not select
the first reply from an incomplete discovery window.

Existing installations, including source-copy workers without a managed receipt,
retain their controller and settings byte-for-byte. Run
`fleet install --configure` to refresh a controller profile while idle. Saved known
pose is preserved during refresh; only initial enrollment installs the declared
berth pose. Local labels/options absent from the profile remain intact, including nested
supply/GPS/automation options. Explicit lists and item maps replace their prior
values rather than accumulating entries.

`fleet update` verifies and repairs managed software, retaining settings. Release
discovery for software-only installation/update does not require the worker to be
at its original enrollment berth. Fresh enrollment and `--configure` still reject
conflicting GPS evidence. Both
commands refuse active jobs, supply acknowledgements and unresolved recovery.
Append `--no-reboot` for inspection or scripting. `--base HTTPS_DIRECTORY` explicitly
selects a source; its version must match the controller's advertised release.
Existing installations retain their recorded source unless overridden. A new
installation trusts the selected controller's advertised source, so enrollment
belongs on a trusted Minecraft network. Hashes check consistency, not signatures.

Profile application uses the existing setup transaction. If interrupted after
software installation, retry `fleet install`; its pending profile marker keeps the
configuration step resumable. Ordinary installer recovery remains available as
`installer --recover`. Do not delete transaction/state files to bypass a failure.

The generated bootstrap invokes the installed profile helper with
[CraftOS shell execution](https://tweaked.cc/module/shell.html#run), carrying the
program-local shell API explicitly. No desktop Python is required by turtles.
