# Loaded mission coverage

Requirement27 needs explicit loaded-area admission. A live heartbeat proves that
a turtle ran recently; it does not establish persistent loading for a future trip.
Use declared loaded areas or a supported stationary loader, retain coverage owners
through offline/reboot recovery, and reject uncovered missions with
`MISSION_BLOCKED_UNLOADED_AREA` plus the missing chunk coordinates.

## Installed hardware and conservative policy

The installed Advanced Peripherals1.20.1-0.7.48r enables its `chunky` turtle
peripheral. Its configured radius is0 and its stale-ticket interval is600 seconds.
The source loads the turtle's current chunk through Forge and updates it each tick;
there is no Lua radius query. Count only that current chunk even if another server
uses a larger radius. Do not change server settings to claim greater coverage.

A dedicated anchor has the chunky upgrade and wireless modem, a known configured
or GPS position, and `chunkLoading.anchor=true`. It remains stationary and cannot
receive ordinary work while providing coverage. Discover actual local `chunky`
hardware; a flag without the upgrade is not coverage. Fixed anchors preserve the
miner's tool/modem slots. Automatic creation/movement of new loaders is not claimed:
when registered coverage ends, report the uncovered area instead of sending a
worker into it. This satisfies the compatibility boundary while later fleet
provisioning remains optional under requirement44.

## Contracts

`chunkLoading={enabled=true,anchor=false,areas={}}` is the default. `areas` contains
explicitly guaranteed chunk rectangles `{minX,maxX,minZ,maxZ}` (block coordinates
use floor(x/16), floor(z/16), including negatives). These are operator-managed
assurances, such as externally force-loaded terrain; they are never inferred from
mining or project bounds. Test fixtures explicitly declare their simulated loaded
terrain. A disabled legacy policy remains an explicit opt-out and is shown in
status; it is not accepted as loaded-mission evidence.

Before assigning a worker, compute a conservative X/Z envelope covering current
pose, depot, target geometry, access/exit routes and bounded side approaches. Fixed
miners require advertised bounds; exploration uses its saved immutable geometry.
Cap a mission at1024 chunks. Cover each chunk through an assured rectangle or an
online, stationary, hardware-backed anchor. Persist the exact provider claims with
the job before assignment; failures roll back. Claims do not expire while the
physical job is outstanding. Offline anchors do not qualify for new claims.

Workers advertise a versioned coverage capability and accept a validated immutable
loaded envelope with assignments. Their movement guard refuses steps outside that
envelope or explicitly configured assurances, before creating a movement intent.
Anchors refuse translation. Controller reservations also enforce coverage so old
or incompatible workers cannot receive strict missions. Restart retains contracts;
changed duplicate grants cannot enlarge authority. Existing jobs without a new
contract require explicit assured coverage during migration, or remain blocked.

The controller releases a coverage claim only when physical work has settled;
private factory work includes output collection. It does not move/reassign an
anchor with outstanding claims. External destruction/removal of loading hardware
can still freeze a turtle; preserve its ownership and report the lost provider.
No Lua program can keep running in an already unloaded chunk without infrastructure.
Remote inventory/farm/station infrastructure must also be inside declared loaded
coverage; capability validation and missing peripherals remain separate guards.

## Integration and evidence

Use one coverage module/ledger shared by generic and mining queues. Add validated
telemetry and assignment fields through existing message cleaners, and a separate
navigation coverage guard alongside the existing collision guard. Expose `chunks`
status (policy, known providers, held claims, blocked missions); setup sharing copies
assured areas/policy but never converts ordinary workers into anchors.

Regression tests cover negative boundaries, unsupported hardware, missing coverage,
conservative routes/depot/approaches, offline owners, save failure/reboot, claim
release, incompatible workers, changed assignments, worker movement refusal and
independent covered work continuing. Native acceptance uses dedicated real chunky
anchors in distant chunks, removes operator force loading, verifies continued
controller/worker execution, and proves a covered cross-chunk mission completes
while an uncovered mission blocks. Inspect actual world blocks and ticket evidence.

Installed-version sources:
[ChunkyPeripheral](https://github.com/IntelligenceModding/AdvancedPeripherals/blob/1.20.1-0.7.48r/src/main/java/de/srendi/advancedperipherals/common/addons/computercraft/peripheral/ChunkyPeripheral.java),
[ChunkManager](https://github.com/IntelligenceModding/AdvancedPeripherals/blob/1.20.1-0.7.48r/src/main/java/de/srendi/advancedperipherals/common/util/ChunkManager.java).
