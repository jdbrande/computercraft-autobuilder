# Automatic construction with bounded material production

Requirements2,14,21 and43 require mining, processing and placement to overlap.
The accepted supply journals already acquire finite batches, settle their production
before staging, survive restart, and prevent duplicate replenishment. Automatic
site preparation already gates construction per verified region. Reuse those two
boundaries instead of adding a second stock ownership ledger.

`build auto` will survey/prepare terrain and begin bounded construction regions as
soon as their preparation is verified. It will not submit a full-schematic central
stock target. Assigned builders request the material for their bounded batches
through the existing supply flow; different builders can place while another
batch is mined or manufactured. Early replenishment remains capacity bounded.
A builder may wait for its first material, and its positive-cargo top-up still
waits for transfer; this design promises overlap across the fleet, not asynchronous
inventory mutation inside an active placement action.

Keep `build prepare` plus `build start` as the explicit full-stock workflow. Persist
an automatic streaming flag on the project run. Never discard an existing owned
full-stock request when continuing a saved legacy project: finish that request
before changing its behavior. Pause/resume, site protection, preparation gates,
region dependencies, inventory leases and final settlement remain authoritative.
Project-linked supply requests and their acquisition workers must remain linked
through final verification and return; no project is complete while its finite
production or cargo owners remain unsettled.

Rejected alternative: decrement a whole-project stock target as workers place.
Current targets mean physical central stock, and placement can include pre-existing
blocks. Reinterpreting them would duplicate the delivery ledger and risk remaking
consumed stock. Region-wide stock reservations could improve throughput later but
are not required to overlap independent finite supply batches safely.

Evidence: fail a controller case where empty stock prevents automatic region
creation, then verify automatic construction issues after preparation without a
whole-project request. Preserve explicit prepare/start and saved legacy runs.
Exercise actual miners, factory and multiple builders with finite initial stock,
observe placement before remaining production completes, restart participants,
and reconcile measured material flows and final ownership. Native acceptance is
useful after deterministic evidence passes. One final review/fix pass, full tests,
release checks and permanent documentation precede integration.
