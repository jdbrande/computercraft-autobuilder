# Project material forecasts

Use `build forecast [name]` to display a project material table. It refreshes while
that view is active and uses the terminal's existing Shift N/P paging.

Each item shows the required construction quantity, observed correct positions,
stored allocation, project reservations, measured ledger transit, worker-held
cargo, estimated outstanding mining/harvesting/crafting/processing and uncovered
quantity. Correct positions include matching pre-existing blocks and exclude air
and upper door halves. Counts refer to the current build or verification pass.
They survive completion-report compaction and retirement of region payloads.

Shared unreserved stock is allocated once in project-name order for this view.
That display allocation does not reserve inventory or change scheduling. Real
ownership still comes from inventory leases, supply journals and physical receipts.
Expected provider output is labeled with `~`; it cannot be spent as physical stock.

Unavailable inventory, legacy progress without material totals, stale offline cargo
and offered supplies whose transfer is in progress remain explicitly uncertain.
The initial offered amount is not added to worker cargo, which could count the same
items twice. The view itself does not submit production, move resources or change
owned work.

Builders and repair workers with positive cargo at or below a quarter of the supply
batch top up before placing their last held item, when the remaining region needs
more. The amount is capped by the configured batch and remaining requirement after
subtracting usable held items. Reserved slots and NBT-tagged inventory do not count.
The existing supply journal owns this top-up through restart and partial transfer.
It waits for stock and returns to the station through the normal resupply flow.

Preparation fill, verification and clearance do not prefetch. Physical placement,
support checks and movement routes finish before an early top-up can begin. At zero
cargo the existing inspected-shortage path still decides whether material is really
needed. Initial full-project preparation and sustained production/build overlap
remain separate pipeline work.
