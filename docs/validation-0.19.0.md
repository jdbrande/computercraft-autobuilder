# 0.19.0 physical logistics acceptance

Scope: registered protected inventory nodes, finite reserved courier batches,
measured private-buffer transfers, automatic stock targets and production requests.
This is the logistics foundation for continuous supply and dynamic fleet scaling.

## Automated evidence

Final reviewed gate:563 Lua tests and18 Python tests passed. Release0.19.0 generation
and `python3 tools/release.py --check` passed; `git diff --check` passed.

New tests first failed, then passed for node configuration/aliases, held endpoint
changes, stock/stand protection, atomic count/capacity grants, mixed source stock,
separate concurrent buffers, partial transfers and staging/collection interruption.
Worker regressions cover pickup/drop interruption, bounded monotone receipts,
changed duplicates and retention of exact completion after acknowledgement.

Two actual controller/courier runtimes with finite fuel pass concurrent hauling,
controller and worker restart, a lost acknowledgement and automatic full-buffer
recovery. Additional regressions cover remote stock loading geometry, source/final
capacity limits, older factory drainage, shared legacy/fuel consumer isolation,
target/inbound accounting, nearest-source routing, source stock targets, one
production request across reboot and waiting for its completion before hauling.

## Final review fixes

Four Important findings were reproduced by six failing regressions, then fixed in
one pass. Unclaimed haul preferences no longer pin a dual-role worker needed by an
older factory; grant time rechecks actual worker ownership. Automatic routing honors
protected fuel and held stock claims, waiting for existing owners before forecasting.
Disconnected unused buffers are skipped in favor of healthy alternatives. Automatic
production requires registered routes from every possible shared output inventory,
preventing repeated manufacture into unreachable storage. Status names the inventory
that needs registration. Existing owned endpoint reconciliation remains strict.

The native trial below predates these admission fixes; focused controller and actual
courier-runtime regressions validate the corrected scheduling behavior.

## Native Minecraft — 2026-10-03

Local PrismLauncher1.20.1, TESTINMG, Forge47.4.10, CC:Tweaked1.120.0 and Advanced
Peripherals0.7.48r. Controller150 and couriers151–152 used real turtle, rednet and
wired inventory APIs. The rig spans approximately `(400..440,299..303,0..4)`.
Existing computers0–9 were untouched. No world backup was created.

Source stock began with64 stone and7 dirt. Destination stock and four private
buffers began empty. Both couriers began with2000 finite fuel. The destination
node target was48 stone; the controller selected workers automatically and split
one request into six8-stone batches. Two independent lanes use z0 andz4. Operator
force loading supplied the declared eight-chunk test envelope; this trial does
not repeat the native chunky-loader evidence in0.18.

The completed trial took171.42 seconds and observed two concurrent active couriers.
A controller restart and courier151 restart with held cargo preserved ownership.
The courier reboot was deferred by the test harness until no physical action was
running. Removing the destination stock's wired modem caused completed cargo to
remain owned in collecting/blocked state. Replacing it with the same inventory ID
resumed measured collection without manual task resume or reassignment.

Independent command-computer reads confirmed:

- Source stock:16 stone and7 dirt; destination stock:48 stone.
- All four private buffers and both turtle inventories empty.
- Courier151 fuel1748; courier152 fuel1892. Both idle at their destination stands.
- Six completed batches; all count, capacity and loaded-mission leases released.
- One completed haul; no production request or extra restock job.
- `logistics` reported `haul:1 completed minecraft:stone 48/48`.

The three test computers were shut down and the eight fixture force-load tickets
plus the observer ticket were removed. The rig and inventories remain inspectable.
Ignored evidence in `dist/live-logistics/` includes setup, continuous state records,
reboot/disconnection events, independent physical reads, settled ledgers and cleanup.

## Findings during live development

The first trial sent the first registered courier to another parked worker's
pickup stand, leaving both waiting. A failing registration-order regression led to
nearest-free pickup/drop selection. The fixture was reset into independent lanes.

A subsequent immediate harness reboot landed during an upward physical move. The
saved pose correctly became uncertain and retained ownership. Independent inspection
located151 at the movement target. That interrupted trial was preserved separately,
then reset; it is not counted as autonomous recovery. The accepted trial used a
reboot between completed physical actions. Ambiguous movement recovery remains a
required later recovery milestone, not evidence supplied by this acceptance.

The clean fixture initially gave the second lane's south-facing wired modems the
north-side peripheral-ID field. Only the first lane was visible. Correcting those
modem IDs let the second courier join automatically after24 stone had arrived;
no material, fuel or manual worker assignment was supplied during that correction.
The remaining batches exercised concurrent operation and the planned restart and
disconnection checks. The preparation script now creates the correct modem faces.

## Limits retained in the fleet ledger

Nodes require wired inventory observation/staging at both ends. They do not discover
unwired storage. Cable/processor/farm volumes beyond registered nodes still require
restrictedAreas until broader infrastructure registration. Shared inventory barriers
retain safety while limiting cross-role throughput. Narrow-route deadlock recovery,
early builder/fuel replenishment, aggregate production above the finite request
limit, final home return, dynamic scaling and full site leveling remain required
subsequent work. Claims never expire merely because a worker goes offline.
