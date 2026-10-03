# Capacity-aware private crafting

Required follow-up to15/16 and prerequisite for44: finite recipes must run when a
smaller batch fits the registered factory. The native0.16 pane trial exposed32
unknown-stack outputs exceeding27 slots even though16 outputs fit. Reuse existing
capacity/count ledgers, private stations and measured transfer journals.

A queued private task is a logical batch preference. Until its first atomic grant,
it does not pin its preferred worker or ingredients. At grant time recheck worker
eligibility and existing storage/factory exclusion. Refresh shared stock; bound the
batch by unreserved ingredients, protected fuel, configured maximum and remaining
logical quantity. Search largest fitting quantity using the existing capacity
allocator with one cached read-only peripheral observation per inventory/slot.
Unknown output stack limits remain1. Select concrete private and central slots, then
checkpoint batch quantities, count claim, capacity claim and empty transfer journals
in one save. Failure restores all four; no physical transfer occurs before success.

Once granted, contracts never resize. Staging, crafting, collection and restart
reconciliation retain their existing behavior. A logical preferred worker can finish
an older task before accepting this grant. A disconnected/full candidate reports its
reason while another station can proceed. Never infer unobserved output stack limits.

Granted production batch offsets identify nonoverlapping intervals in the operation.
Logical preferences reserve no operation coverage: at grant, choose the first remaining
interval again so an unusable station cannot withhold work from another worker. A
smaller granted batch leaves an uncovered interval; scheduling fills the first gap
without changing any other batch's offset or repeating completed work. New queue
identities remain unique. Older unstarted stock-only claims may be atomically
cancelled and their tasks retired before replacements are planned. Preserve any
capacity owner, assigned worker, staged stock or unresolved journal unchanged.
Cancelled historical tasks do not count as production coverage or completion.

Tests cover high-yield panes, heterogeneous/full stations, ingredient contention,
worker reassignment, immutable owned quantities, failed grant saves, old checkpoints,
controller/worker reboots and exact final stock. Native acceptance uses real Crafty
stations with finite ingredients and no output sample. One final whole-branch review
and consolidated fixes precede integration; then continue all fleet requirements.
This does not complete continuous multi-project production or dynamic fleet scaling.
