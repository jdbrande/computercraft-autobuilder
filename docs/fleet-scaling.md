# Automatic fleet allocation

The controller reevaluates mining, hauling, crafting, clearing and building demand
as jobs, inventory and worker telemetry change. Newly registered suitable turtles
join useful work automatically. Existing physical ownership always takes precedence:
reducing a limit lets assigned workers finish, unload and return before becoming idle.
Rescue, refueling, home returns and temporary foundation-access restoration continue
independently of ordinary role limits.

Use `fleet status` for each role's target, active and idle counts, queue depth,
remaining work, observed delivery rate, estimated duration and limiting condition.
The fleet terminal view refreshes during operation. A `~` rate is a bootstrap
estimate; completed jobs replace it with the last32 physical completion samples.
Zero-yield mining trips contribute elapsed time without inventing delivered items.
Private crafting counts centrally collected output and its durable factory interval.

Use `fleet limit mining 0 4` to permit up to four miners. The same command accepts
`hauling`, `crafting`, `clearing` and `building`. Bounds are integers from0 through128,
with minimum no greater than maximum. A maximum of zero stops new ordinary work for
that role. A minimum applies only when useful independent work and eligible workers
exist; it does not keep workers busy after demand drains. Commands persist across
controller restarts. Editing the configured scaling settings supersedes saved limits.

Equivalent settings in `autobuilder/settings.lua`:

```lua
scaling = { roles = {
  mining = { min = 0, max = 4 },
  clearing = { min = 0, max = 3 },
  building = { min = 0, max = 3 },
} },
```

Omitted roles retain defaults of minimum0 and maximum128. Start with defaults unless
physical infrastructure requires a lower concurrency cap. The allocator estimates
work over a two-minute window and favors specialists before consuming shared workers.
Ready bottlenecks share flexible capacity; unavailable or gated work cannot claim an
idle worker merely because its queue is large. Surveys and construction expose bounded
independent regions as registered capacity grows.

Targets remain estimates. Equipment, finite fuel, dependencies, protected areas,
loaded coverage, traffic, station capacity, material claims and supply serialization
still govern actual dispatch. More workers cannot bypass a disconnected inventory or
an unavailable furnace. Workers already offline with owned work continue to count as
owners until their ordinary recovery resolves the task. No automatic turtle
manufacturing or deployment is assumed.

Significant target and bottleneck changes enter the existing log; the controller
retains the most recent32 decision records. Completed-task markers and rate samples
share a checkpoint, preventing duplicate samples after restart. Old jobs without a
durable work-start timestamp do not contribute fabricated durations.

Implementation and acceptance progress is recorded in [fleet progress](fleet-progress.md).
