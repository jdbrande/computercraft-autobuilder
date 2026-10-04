# Reachable worker inventory recovery

Requirement25 asks for recovery jobs when an unrecoverable worker still has reachable
inventory. Requirement26 retains the original task, territory, pose and expectations
while offline. Extend the existing controller/worker freeze and measured-transfer
boundaries; never infer that an offline timeout authorizes taking a worker's cargo.

A confirmed blocked worker can be quarantined for cargo recovery through an explicit
controller recovery command. Once requested, the controller creates and runs recovery
jobs automatically, selecting healthy fueled couriers and registered recovery storage.
The original worker stays held, its task and physical territory remain owned, and its
ordinary action loop cannot run while another worker takes its items. A blocked return
never permits digging a route. Unknown/pending poses and unresolved physical inventory
journals must reconcile before freezing; offline recipients wait for contact.

Reuse the fuel-rescue identity check, immutable handshake, durable receipt ordering,
per-cell navigation, conservative round-trip fuel budget and bounded retry semantics.
A recipient freeze snapshots all16 slots. Recover one exact stack at a time: the donor
selects the recorded slot and drops only after confirming the courier's adjacent
computer ID, while both sides reconcile their own checkpointed inventory deltas.
No world drops and no unverified suck from unknown inventory. Restart before or after
a transfer cannot create a second delivery; changed contracts, unrelated inventory
changes and incomplete receipts retain both owners for reconciliation.

A courier deposits into its registered recovery buffer, with exclusive destination
ownership and capacity reserved before pickup. Tagged stacks retain their exact item
and NBT identity; they are stored for recovery rather than credited as ordinary factory
stock. The courier's own fuel/tool slots remain reserved. Recipient cargo leaves its
old expectation only against measured donor and courier receipts, and recovered stock
is usable only after measured storage delivery. A worker remains quarantined after
recovery; releasing an unrepaired task is not an inventory-transfer side effect.

Use current storage/job services where they provide the needed contracts. Introduce
only the missing recovery job/handshake, not another scheduler. Test duplicate and
reordered messages, disconnect/reboot, failed checkpoint rollback, partial capacity,
wrong recipient identity, tagged items, fuel shortage, blocked route and preserved
original ownership. Native acceptance uses a blocked stationary worker, real courier
and registered chest, includes an interrupted transfer, and independently checks
exact inventories and fuel. One final review/consolidated fix pass and complete gates
precede integration. Later scheduling, monitoring and integrated scale acceptance
continue without a milestone pause.
