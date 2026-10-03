# Let the turtles gather the building materials

For miners that find deposits automatically, use the [exploration guide](autonomous-mining.md).
The resource-specific fixed-area setup below remains supported.

The controller can now run different miners at the same time, make missing blocks,
and start building when the materials arrive. Type **8**, then Enter, on the
controller to see each resource and its assigned turtle.

Your completed small test stays completed. Updating does not restart it.

## Use your seven workers

Keep turtle **2** as the builder. A useful starting arrangement for the other six:

| Turtle | Job | Type this on that turtle |
| --- | --- | --- |
| 3 | Stationary crafting turtle | `setup crafter` |
| 4 | Cobblestone and coal | `setup miner stone,coal` |
| 5 | Sand | `setup miner sand` |
| 6 | Clay balls | `setup miner clay` |
| 7 | Diorite | `setup miner diorite` |
| 8 | Cobbled deepslate | `setup miner deepslate` |

Those commands work inside Autobuilder as well as from the shell after startup.
They open a wizard; they do not immediately move the turtle.

**A miner must be near the material it is collecting.** Put the sand miner at a
sand deposit and the clay miner at a clay deposit. A small mine in ordinary stone
will not magically produce sand, clay or deepslate. Use dry, accessible deposits;
liquids and protected blocks stop excavation. Other allowed terrain may be dug
while reaching the requested material.

## Set up each miner

1. Place a chest or barrel. This is that miner's **deposit chest**.
2. Connect that chest to the controller's wired network. Right-click its wired
   modem so the name appears and the modem lights up.
3. Put the mining turtle **on top of that chest**. Give it a pickaxe and wireless
   modem. The space above the miner must allow its route to the mine.
4. Put coal blocks in **slot 15**: bottom row, third box. Leave slot 16 reserved.
5. Type its `setup miner ...` command from the table.
6. Answer the position and facing prompts. Without GPS, use F3 **Targeted Block**
   for the turtle's coordinates, not your player's coordinates.
7. Enter accepts the suggested adjacent **8 x 8 x 3** mining area. Read the shown
   corners. Put miners far enough apart that their mining areas do not overlap.
   Keep the cathedral, chests, machines and cables outside every mining area.
8. Type `yes` to save. If you ran setup from the shell, type `reboot` afterward.

The controller keeps each mine assigned to its owner, including when that turtle
disconnects. It does not send another turtle into an occupied mine. If the bounded
survey cannot find enough of its resource, the job stops and reports the shortfall;
it does not search the entire world indefinitely.

## Add crafting and smelting

For turtle 3, use a **crafting table upgrade and wireless modem**, with no pickaxe.
Keep all 16 inventory slots empty. It stays parked and does not need movement fuel.

Put an empty **INPUT chest above** it and a different empty **OUTPUT chest below**
it. Put an external wired modem beside the turtle and connect it to the same wired
network as both chests and STOCK. Activate the chest modems. Run `setup crafter`
on turtle 3 and select the input, output and STOCK names shown by the wizard.
Choose the physical names carefully; the computer cannot infer which remote chest
you placed above the turtle.

Place one or more **ordinary furnaces**, each with an activated wired modem and
cable to the controller's network. Then type `setup factory` on controller **1**.
It finds the furnaces. Add each miner's deposit chest to STOCK when prompted.
Do not choose the builder's SUPPLY chest or the crafting INPUT/OUTPUT chests as STOCK.
Use the same stock inventories in the crafter's setup so it can access raw materials.

Keep the area above the builder's parking place clear. The updated builder requests
coal through its regular SUPPLY chest when its carried fuel runs out; a fuel chest
above the builder would obstruct its return route. Miners may use a fuel chest above
their depot if it does not obstruct their configured entry route.

## Start a project with one command

For an already imported blueprint, type:

```text
build auto my_project_name
```

The controller checks stock, sends missing raw-material jobs to eligible miners,
crafts and smelts required outputs, builds, and verifies. `build pause NAME` stops
new work and pauses factory/build tasks. Already assigned miners finish their safe
return. `build resume NAME` continues the saved project.

To construct the simplified full cathedral, first choose a **clear 416 x 239 site**
with clear travel access to the builder's supply depot. The small test's automatic
clearing covers only its 8 x 8 site; it does not clear this full cathedral footprint.
The full structure is 256 blocks tall. In the Overworld its origin must be at or
below Y=62 to leave clearance for the turtle. Its lowest block coordinate is the
corner you enter; it extends east (+X) and south (+Z).

```text
cathedral start X Y Z
```

Replace X, Y and Z with the chosen corner's actual numbers. This queues the
cathedral behind existing work. It downloads one small batch at a time, obtains
its materials, builds and verifies it, and then continues. Every chunk in a lower
layer finishes before a higher layer starts. Type `cathedral` for status,
`cathedral pause` to pause, or `cathedral resume` to continue.

The cathedral still needs **oak and spruce wood**. Either put logs/planks into
STOCK or configure the [managed tree farms](renewables.md) and a logging-capable
worker. Miners do not harvest arbitrary forests. The controller reports missing
farm sources rather than treating those materials as available. Keep all active
workers, stock, farms, furnaces and construction chunks loaded.

## Updating your existing computers

Finish active physical jobs first. On each computer, press **Q**, type `update`,
then type `reboot` after it succeeds. Settings and saved work are preserved.
Use [installation instructions](installation.md) for new computers and offline
core installations. Full cathedral streaming currently needs HTTP access to the
repository; its 20 MB of optional data is not included in each core installation.

This release is covered by simulated hardware tests. The full 770,617-block
cathedral has not been completed in a live Minecraft acceptance run. Exhausted
deposits, obstructed routes, chunk unloading and missing hardware still require
attention; the program reports these instead of silently skipping work.
