# Durable inventory ownership

Prerequisite for fleet requirements 11–15 and fuel/logistics concurrency. Extend
existing queues and physical journals; do not introduce a second scheduler.

The controller owns a persisted inventory ledger keyed by immutable job ID. A
claim contains input quantities, expected output quantities, cumulative confirmed
withdrawals/deliveries, optional project association and explicit transit counts.
Reservations subtract only inputs still in shared storage. Expected output never
becomes available stock. Offline owners retain claims. Duplicate identical claims
are idempotent; changed duplicates are rejected. Failed checkpoints roll back.

Views distinguish measured physical stock, available stock, unwithdrawn reserved
stock, in-transit items, outstanding expected production and project demand.
Unknown storage remains unknown. Counts are bounded nonnegative integers; reserve
is atomic across all ingredients. Fuel reserves are protected when granting new
factory claims. Shortfalls remain queued and recover when stock arrives.

New production CRAFT/SMELT jobs declare exact ingredient/fuel and output claims.
They cannot be assigned or act before a durable grant. Existing saved jobs retain
the old exclusive behavior during migration. Worker crafting journals count
confirmed withdrawals; bounded cumulative receipts update the controller claim.
Furnace counters already expose exact loaded inputs/fuel and delivered output.
Receipt updates are monotonic/idempotent and cannot exceed the declared contract.
Completion releases unused claims only after physical completion evidence; a
never-started cancellation cannot discard transit or withdrawals.

Keep the global factory barrier throughout this milestone. Count reservations do
not make existing whole-chest transfer observations safe under concurrent writes.
The following parallel-factory work must stage independently owned station inputs
and replace shared whole-inventory observation with owned-slot journals before
relaxing that barrier. Destination-capacity reservations belong with that staging
and logistics integration; do not claim them from this count ledger alone.

Acceptance: two competing jobs cannot claim the same ingredients; malformed and
changed claims fail; partial and repeated receipts conserve counts; restart/offline
owners and checkpoint failures preserve grants. Runtime tests verify no factory
hardware call or worker assignment before reservation, safe shortage recovery and
normal full-chain completion. Live acceptance should exercise the new counters
on the existing furnace/Crafty rig. Extend resource status with the logical views.
