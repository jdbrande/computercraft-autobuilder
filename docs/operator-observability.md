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

Structured-event hooks, shared dashboard projection and native monitor acceptance
remain under implementation. No0.38 release acceptance is claimed yet.
