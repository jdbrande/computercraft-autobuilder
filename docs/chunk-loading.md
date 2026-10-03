# Loaded mission coverage

Missions require confirmed coverage for the worker, depot, route, work area and
bounded side approaches. The default policy is enforced with no assumed loaded
terrain. A heartbeat or a configured mining boundary does not establish coverage.
Use `chunks` on the controller to see coverage, providers, held claims and exact
`MISSION_BLOCKED_UNLOADED_AREA` reasons. Independent covered work can continue.

## Stationary chunky anchors

On Advanced Peripherals, install a chunky upgrade and a wireless modem on a spare
turtle. Configure its controller ID, place it in the chunk to keep loaded, then run
`setup anchor` and reboot. Setup checks the actual `chunky` peripheral and obtains
GPS coordinates or asks for the turtle block coordinates. It does not move the
turtle or consume fuel. Anchors advertise only their current chunk; server radius
settings are deliberately not inferred. Place anchors throughout the route and
work envelope, within rednet reach of the controller.

An anchor receives no ordinary task. Its provider claims persist until the covered
physical work finishes, including private factory output collection. An offline
or missing anchor cannot qualify new missions. Existing ownership remains held;
restore the same loader and reconnect it before expecting its area to resume.
External removal can unload workers: software cannot execute in unloaded terrain.

The tested Advanced Peripherals0.7.48r configuration uses radius0 and a600-second
stale-ticket interval. Its Forge tickets are separate from vanilla `/forceload`.
Stopping a computer does not promise immediate ticket removal; removing an anchor
can leave its old ticket until the mod's expiry cleanup.

## Explicitly assured terrain

For terrain kept loaded by infrastructure outside this fleet, add chunk-coordinate
rectangles to the controller's `/autobuilder/settings.lua`, then reboot:

```lua
chunkLoading = {
  enabled = true,
  areas = {{minX = 0, maxX = 1, minZ = -1, maxZ = 0}},
}
```

These are operator assurances, not commands that load the world. Use
`math.floor(blockCoordinate / 16)`: block-1 belongs to chunk-1. Include depots and
approaches, not just the desired building. A mission uses a conservative rectangle
with a two-block horizontal margin, bounded to1024 chunks. Larger schematics must
use finite regional missions. There may be up to64 assured rectangles.

Workers receive immutable coverage grants with their assignments. `setup chunks`
on an idle worker copies the controller's validated coverage policy and assurances;
it preserves the worker's local anchor role. Ordinary builder setup also copies
available coverage settings. No setup message turns a builder into an anchor.

For an upgrade with already active jobs lacking grants, explicitly assured areas
on the controller and worker permit migration. Otherwise ownership remains intact
and movement blocks. Do not erase checkpoints. New assignments require a worker
advertising the coverage protocol. A disabled policy (`enabled=false`) is an
explicit legacy opt-out, shown as `DISABLED`; it is not chunk-loading evidence and
does not remove the limits of a saved active grant.

## Scope

This is loaded-mission compatibility using existing loading infrastructure. It
does not manufacture, deploy or move anchors automatically. Remote wired storage,
processors and farms must also remain loaded; unmapped peripheral names do not
reveal their world coordinates. Infrastructure mapping and automated provisioning
remain separate fleet work. See [native acceptance](validation-0.18.0.md).
