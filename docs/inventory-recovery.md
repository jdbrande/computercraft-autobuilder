# Reachable worker inventory recovery

Use `worker recover <id>` on the controller when a worker is blocked and cannot
safely return. Use `recoveries` to inspect the request and its current error.
This explicitly quarantines that worker for cargo collection. A timeout alone
never permits taking an offline worker's inventory.

The donor must reconnect, have a confirmed stationary pose and a blocked owned
assignment, and finish any physical inventory journal or pending supply receipt.
The controller selects an idle healthy courier with enough return fuel and an
empty registered logistics buffer beneath its configured depot. The buffer needs
space for every occupied donor slot. Routes must be reachable without digging,
with the normal movement reservations and loaded-chunk assurances.

The courier approaches above the donor. Both turtles verify the adjacent computer
ID; the donor transfers one exact stack at a time and both sides persist measured
receipts. Reboots reconcile transfers before proceeding. The courier preserves its
own fuel/tool inventory and deposits only the items it received. Between settled
trips it can refuel at its registered home station; the recovery keeps its courier
and buffer reservation while that separate fuel job finishes. Storage capacity
is reserved before pickup, and completion waits for independent buffer observation.

Plain recovered items are moved through journaled wired transfers into the buffer's
registered central storage node. Tagged tools/items retain their exact NBT identity
in the private buffer and are not counted as ordinary production stock. Collect
those tagged items after the recovery completes before reusing that buffer. If
central storage is full or disconnected, the request retains the buffer and reports
that condition while unrelated controller action services continue. An unresolved
transfer journal still takes precedence over other inventory actions. Three consecutive empty transfers require correcting the physical
inventory problem and retrying `worker recover <id>`.

Recovery does not repair the original worker or release its original job, region,
route, production contract or other unresolved ownership. It stays quarantined,
even after its cargo reaches storage; ordinary resume/setup commands cannot silently
restart a task whose inventory was removed. Offline or ambiguous-pose workers and
unsettled task journals require their existing reconciliation before collection.
