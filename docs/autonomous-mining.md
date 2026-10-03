# Automatic exploration mining

This milestone lets several miners discover materials for `build auto NAME`.
It uses the existing crafting, furnace, supply and construction setup. It does not
provide chunk loading, fuel rescue or a direct binary `.schem` import command.

## Set up the controller

Finish active work before updating. Preserve settings and checkpoints. Install the
same release on the controller and every exploration worker.

Run `setup exploration` on the controller. Enter a base position, horizontal
radius, dimension height limits, search heights and a box protecting your base.
The default radius is 64; default search heights are base Y minus/plus 16.
Include storage, cables, machines and farms in the protected box or existing
`restrictedAreas`. Imported projects also receive automatic protection.

The boundary must stay loaded and within wireless modem coverage. The wizard asks
you to confirm this because the software cannot guarantee chunk loading. There
can be at most 4096 sectors of 8 by 8 by 3 blocks; reduce radius or search height
if setup reports this limit.

## Set up each explorer

1. Equip a mining turtle with a pickaxe and wireless modem. A Geo Scanner in
   reserved slot 16 is optional. Keep fuel in reserved slot 15.
2. Park it above a dedicated deposit chest or barrel. Wire that inventory to the
   controller and include it in STOCK with `setup factory`.
3. Run `setup miner explore`. Provide its actual coordinates/facing when prompted.
4. Enter an exit beyond the protected base. Clear the entire route first: vertical,
   then X, then Z. The program may traverse this declared exit but cannot dig it.
5. Review and save. This setup does not move the turtle or burn fuel. Provide enough
   fuel before dispatch; pre-fuel it using CraftOS or an existing fuel source.
6. Use separate parking places and exits. Miners wait for occupied routes and cannot
   own overlapping search sectors. A narrow shared exit can limit concurrency.

Miners return to their own deposit chests to unload. They can refuel through the
existing configured inventory behavior, but fuel delivery to each station is not
automatic in this milestone. An insufficiently fueled idle turtle will not be
assigned a trip. A busy miner reserves enough fuel to retrace its recorded trail.

## Start and inspect work

Convert/import a supported schematic using the [blueprint guide](blueprints.md),
then use these commands in the controller application:

```text
build auto my_project
exploration status
exploration pause
exploration resume
```

The controller selects sectors automatically, tracks observations and divides
material demand into trips of at most 64 requested items. A trip can deliver less
when its survey ends or it returns for cargo/fuel. The remaining demand stays open.
Stock becomes available after actual unloading; an observed ore is not stock.

`build pause NAME` stops new work for that project and requests safe returns from
its explorers. `exploration pause` requests returns from all explorers. A blocked
or uncertain return remains visible and keeps its territory owned.

If the search area is exhausted, use `exploration expand 96` only after ensuring
that the wider area is loaded, within modem coverage and appropriately protected.
Expansion cannot shrink the old boundary or exceed the sector cap. It survives
controller restart and retains previous surveys. It does not change existing trips.
For different heights or a new base, finish work and run setup again.

## Reported stops

- No compatible worker: register an updated exploration turtle with suitable fuel.
- Insufficient round-trip fuel: fuel the turtle or shorten the operating boundary.
- Search envelope exhausted: expand permitted territory or supply the missing item.
- Protected/blocked route: inspect the reported route and keep infrastructure protected.
- Full deposit chest: make room in the wired stock inventory.
- Uncertain movement/dig/transfer: preserve inventory and checkpoint files; reconcile
  the reported physical state before resuming. Do not delete saved work to retry it.

For this milestone, miners finish unloading before factory operations use the
shared stock. Concurrent production with inventory reservations is a later fleet
milestone described in [the full requirements](fleet-requirements.md).
