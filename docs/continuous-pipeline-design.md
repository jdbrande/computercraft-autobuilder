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

## Final review corrections

Pause/resume now follows every project-linked finite request, including supply
acquisition groups and provider jobs. New ordinary automatic runs clear a completed
stock-only policy; active saved stock-only requests retain it. The shorthand command
regression checks idempotence without expecting a whole-project request.

The first overlap assertion was inadequate: it combined historical placement with
a later pending request. It has been replaced by an assertion at the actual successful
placement call while another miner is away from its depot on an active physical
acquisition. The fixture uses independently prepared regions separated beyond the
traffic exclusion margin. Adjacent regions are deliberately serialized by ownership.
The strengthened regression failed the original timing scenario and passes the
independently eligible one, including restart and exact material conservation.

Review also exposed an inherited interruption window during the first site save.
Acquisition policy and automatic survey-to-preparation continuation now precede
that checkpoint. A power-cut regression fails without both durable flags and
passes through final construction after reboot. This closes an observed recovery
bug rather than deferring it solely because it predates this milestone.
