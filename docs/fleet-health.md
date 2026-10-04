# Worker hardware and software health

Workers publish optional bounded health evidence with registration and heartbeats.
The controller's worker view shows software version/status and equipped tools.
Configured roles remain opt-in. Hardware observation never moves, digs, crafts or
swaps upgrades; missing old equipment APIs report unknown. Equipment inspection
uses CC:Tweaked's read-only [getEquippedLeft/Right APIs](https://tweaked.cc/module/turtle.html#getEquippedLeft).

New ordinary jobs require their movement, placement, digging or crafting APIs.
Known mining equipment needs a pickaxe; harvest/clearing accepts pickaxes, axes or
shovels. Unknown legacy equipment retains compatibility. A new heartbeat after
repair restores eligibility. Existing assignments, routes and inventory ownership
remain intact; return, refuel and rescue admission remains available.

At startup, workers compare managed files with the installed manifest and receipt:

- `verified`: selected role files match the manifest and receipt.
- `modified`: managed code is missing, edited, or differs from its receipt.
- `unmanaged`: no installation receipt exists, as with a development source copy.
- `unavailable`: metadata cannot be read or validated.

Modified/unavailable workers receive no new ordinary jobs. Restore the managed
installation and restart to recompute software health. This is a consistency check,
not authentication against a maliciously replaced manifest. The installer supports
custom root `startup.lua`; integrity verification excludes that file and local
settings/state. Heartbeats refresh hardware evidence but do not rehash or download
software. Unknown legacy and unmanaged source copies retain compatibility.

Single-command fleet onboarding/configuration/update remains the next dependent
milestone. This feature supplies its hardware and software evidence.
