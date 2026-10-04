# Inventory infrastructure protection

Register the physical blocks behind wired inventory names on the controller:

```lua
inventoryAreas = {
  ['minecraft:furnace_0'] = {
    min={x=10,y=64,z=2}, max={x=10,y=64,z=2},
  },
  ['minecraft:chest_7'] = {
    min={x=12,y=64,z=2}, max={x=13,y=64,z=2},
  },
}
```

Use actual container coordinates. Include both halves of a double chest and the
whole processor structure. Extra cells may protect cables or casings. Existing
logistics nodes, private home buffers, supply stations and fuel stations already
provide their container geometry; explicit bounds may enlarge that coverage.
`restrictedAreas` remains useful for infrastructure without an inventory name.

`setup factory` asks only for missing bounds, including disconnected configured
endpoints and endpoint names reported by registered crafters. Enter three integer
coordinates for a single block or six for inclusive minimum/maximum corners.
`cancel` leaves the settings unchanged. Basic controller setup also locates its
stock and supply chests. A wired peripheral name alone cannot locate its block.

Old configurations still load. Missing locations produce an explicit inventory
name and block new digging/placing assignments and mutation grants. Observation,
movement, safe returns and factory reconciliation remain available. Register the
missing bounds and restart the controller. Use current worker software so a
stationary crafter reports its local buffer/input/output names; for older workers,
register those endpoints explicitly in controller configuration.

The accepted geometry is checkpointed separately from factory contracts. Offline
workers do not release it, and a project's own volume cannot exempt it. Moving or
removing geometry while work, leases or journals remain owned is rejected. Adding
geometry across owned excavation territory, routes or reserved action cells also
requires settling that ownership first. Finish or reconcile that work before
changing its physical infrastructure; a restart is not an ownership release.

At most512 named inventory bounds are accepted. Contained protection boxes are
compacted without weakening protection. A mining mission requiring more than128
boxes reports the existing explicit planning limit. Consolidate nearby physical
infrastructure into a truthful larger registered/restricted volume.
