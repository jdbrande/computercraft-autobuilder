# Material forecast and early replenishment acceptance

Accepted0.27.0, implementation `c755627`. Complete release gates and native
acceptance passed. The full fleet roadmap remains in progress.

## Automated evidence

-846 Lua tests passed on the final source (`/tmp/fleet-027-final-full.log`).

-18 Python tests passed with the repository virtual environment.
- Release generation, `python3 tools/release.py --check` and `git diff --check` pass.
- Report/network/forecast/ledger checks cover bounded per-item correct-position
  totals, malformed/regressing reports, retirement, shared-stock allocation,
  offline/legacy uncertainty and read-only command refresh.
- The broader project runtime suite passed before final supply fixes. The final
  full suite includes every correction below.
- Actual controller/explorer/builder chain starts replacement mining while one
  cobblestone remains held and no placement has occurred. Controller and worker
  restarts preserve one mined, one supplied and two placed items.
- Actual supply runtime with thirteen occupied usable slots passes64- and16-item
  stack limits across power loss after partial receipt:65 placements,64 supplied
  items, empty staging and released ownership.
- Actual HARVEST and FARM executors retain forecast coverage through collection,
  partial deposit, restart and final delivery. Held output is distinct from future
  yield and measured delivered output; unknown evidence remains explicit.

The single final review found two important bugs: unbounded receiving capacity
could permanently strand supply staging, and harvested progress was mistaken for
physical delivery. Both have failing-before/passing-after regressions. An earlier
chain test also exposed spending deposited stock before its acquisition settled;
first staging now waits for its linked finite production request, while already
owned offers still drain. This prevents replacing stock just consumed by its owner.

## Native Minecraft acceptance — 2026-10-03

PrismLauncher1.20.1 / TESTINMG, Forge47.4.10, CC:Tweaked1.120.0 and Advanced
Peripherals0.7.48r. Separate fixture near `(1440,300,0)` used controller225,
builder226 and inspection explorer227. Builder started with1000 finite fuel;
miner with2000. Wired storage, private supply/home/fuel chests, twelve stone
foundation cells and operator-held coverage across ten chunks were provided.
No world backup was made. Existing live scaling fixture212–218 was independent.

The ordinary `build auto early_supply` project requested two cobblestone blocks
at `(1454..1455,300,0)`. Initial central stock contained two cobblestone and four
coal. After the first one-item offer, the harness deliberately removed the other
stored cobblestone to model external stock loss. No replacement finished building
material was added. A staged stone deposit supplied the missing raw item.

The retained snapshot shows the builder still held one cobblestone, its report had
zero completed positions, its second one-item supply request was ungranted, and
miner227 owned the replacement mission. Thus acquisition began before zero cargo
and before the first placement. The project reached `built` with two correct
positions; both workers returned empty. Independent observer90 checked both world
blocks, all twelve foundation cells, the mined deposit and physical inventories.
Builder ended with768 fuel and miner with1996.

A second run removed the two finished blocks, reset two initial cobblestone and
provided one new stone deposit. The same one-item stock-loss injection ran. At the
positive-cargo replacement request, the harness rebooted both controller225 and
builder226 through their normal startup path. They retained the existing supply
and mining ownership, finished two correct blocks and returned empty. Final fuel
was536 for the builder and1986 for the miner. All four finite production requests
across both runs completed, with no active supply owner or mining trip.

All22 independent final checks passed. Computers225–227 were shut down and all
ten fixture force-load tickets removed; observer command receipts confirm cleanup.
The player was not moved. Audit startup/state copies, exact setup/stock-loss
commands, restart snapshots and observer receipts are under ignored
`dist/live-supply-forecast/`.

## Limits

The fixture is staged and operator-loaded; it does not establish arbitrary terrain
coverage or automatic chunk loading. Native acceptance covers early supply, not
native harvesting forecast telemetry; actual farm executor simulations cover that
accounting. The forecast is read-only and allocates shared unreserved stock once
by project name. Correct totals describe the current build/verification generation.
An individual worker waits during replenishment. Initial production/construction
overlap remains the dependent0.28 milestone, not an acceptance claim here.
