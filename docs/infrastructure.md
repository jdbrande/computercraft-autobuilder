# Bounded depot expansion

Automatic depot expansion monitors the number of **empty inventory slots**, using
the wired inventories in `storageInventories`. It does not estimate room remaining
inside partial stacks. Enable it with an explicit, absolute footprint:

```lua
autoDepotExpansion = { enabled=true, freeSlots=2 },
depotExpansion = {
  {x=110,y=63,z=-200,name='minecraft:stone',state={}},
  {x=111,y=63,z=-200,name='minecraft:stone',state={}},
},
```

`build.enabled` must also be true. At or below the threshold, the controller queues
that one footprint. A builder places it using the existing construction, supply,
movement-reservation, and restricted-area checks. `expand` requests the same plan
manually, regardless of the automatic trigger flag. Neither command nor repeated
low-capacity observations creates additional copies of the expansion.

The plan contains 1–512 explicit non-air cells. Each must have a supported placement
strategy; partial strategies retain their support/access requirements. Duplicate
coordinates, malformed states, unsupported blocks, and restricted target/access
cells are rejected before dispatch. Dependencies determine placement order. In
particular, chests and barrels remain unsupported: adding them to this plan produces
a visible error rather than a claimed storage installation.

This builds the configured **depot footprint**. It does not place, wire, or register
new storage inventories, create new storage capacity by itself, or generate a tree
farm layout. The operator installs any additional containers/network connections
and adds their peripheral names to `storageInventories`. Existing terrain conflicts,
shortages, and full turtle inventories use the normal construction blocking and
recovery behavior. There is no unbounded excavation or automatically invented
expansion geometry.

After construction, the controller queues independent verification of every
footprint cell. Only a report confirming all cells as correct, with zero defects or
inaccessible cells, marks expansion `completed`. A completed BUILD task alone does
not count as verified infrastructure. Verification failures remain visible and do
not start another automatic expansion.

The checkpoint retains `automation.infrastructure`, including the immutable plan,
status, errors, and build/verification job IDs. Persistent queue keys reconcile a
restart between task submission and saving its returned ID. Changes to
`depotExpansion` after the first request do not alter that in-flight plan or start a
second one. Disabling the automatic flag prevents new triggering while existing
owned tasks continue through their normal lifecycle. Preserve checkpoints when
reconciling blocked jobs; resetting expansion state can discard physical ownership.

`core/infrastructure.lua` exposes `new(app, config, environment, queue)`, then
`tick()` and `request()`. Its `state` is the persistent infrastructure record.
The environment requires wired peripheral `size()` and `list()` calls only; the
service never moves inventory or turtles itself. Unreadable or malformed capacity
responses block triggering rather than being treated as free space or full storage.
The desktop tests cover threshold boundaries, snapshot/restart deduplication,
unsupported plans, checkpoint failures, and independent verification outcomes.
