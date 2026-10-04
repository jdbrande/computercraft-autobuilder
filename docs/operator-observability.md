# Operator controls and diagnostics

Candidate0.38 retains terminal character, paste and key events while a native
peripheral call yields. The main runtime coroutine executes commands in order.
Each queue is bounded:128 network messages and128 operator events. Input overflow
rejects the whole current line, including text typed before the stall. Press Enter
and retype; no truncated command is executed. Commands longer than256 characters
are rejected in the same way. Pending local script requests discarded by overflow
receive an explicit correlated failure. Network protocols retain their retries.

A local CraftOS program running in parallel can submit:

```lua
os.queueEvent('autobuilder_command', 'my-request-1', 'fleet status')
-- Listen for: autobuilder_command_result, requestId, success, result
```

Request IDs are nonempty strings up to64 characters; commands are single lines
up to256 characters. Results are at most1,024 characters. This is a local event
interface to the ordinary dispatcher. It does not provide durable request-ID
idempotence: if a program times out or reboots before receiving its result,
execution is unknown. Inspect fleet state before resubmitting a mutation.

Owned jobs retain traffic waits with the first timestamp, target coordinate,
mutation/movement distinction, denial reason and blocking worker when known.
Repeated identical retries preserve the timestamp and produce no new checkpoint.
A wait becomes prolonged after30 seconds. Any successful subsequent grant clears
the wait. Offline workers keep their cell and task ownership; diagnostics never
release those reservations. Inspect the named worker or route and settle the
underlying condition before resuming work.

Configure a controller monitor with `monitor={name='monitor_0',scale=0.5,interval=1}`
in settings. The wired name or side must resolve to a native monitor. Tap to advance
pages. The optional monitor redraws at most once per configured interval and only
when its rendered page changes; resizing/disconnection/reconnection leave work
running. Its errors appear in the terminal footer. `dashboard` uses the same cached
projection in the terminal. Stock marked unknown is not shown as zero. Material
forecasts are estimates, not inventory claims; verification counts refer to the
verification phase. Display rows are not added to durable checkpoints.

Aliases include `fleet workers`, `fleet worker <id>`, `project list`,
`project status|pause|resume <name>` and `storage status`. Existing build, fleet
limits, resources, logistics, exploration and recovery commands remain available.

Significant events go to `<logDir>/<role>.events.jsonl`, with the existing byte and
rotation limits. Records include event/time/computer/runtime boot and relevant
project/request/job/worker/lease/receipt IDs. They cover committed assignment,
ownership recovery, task/project/production transitions, requirements, shortages,
receipts and stock claims; worker availability, observed stock, diagnostics and
changed role allocations are also recorded. Repeated heartbeats, resends and
unchanged retries are omitted. Whole JSON records are never truncated. Oversized
records or write failures are reported without undoing a domain checkpoint.

Receipts identify their destination. A mining-depot receipt, managed inventory
receipt and later stock observation are different evidence of the same physical
pipeline; do not add them together as newly created items. A crash between a
checkpoint and its log append can omit an event. Logs are diagnostic evidence,
not a transactional ledger or exactly-once replay stream.

Candidate0.38 native acceptance and final gates are still pending.
