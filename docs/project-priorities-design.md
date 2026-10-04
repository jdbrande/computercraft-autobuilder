# Project priorities and travel-aware scheduling

Requirements 30–31 call for concurrent projects whose relative priority controls
new work and resources, subject to existing physical commitments. Keep the current
queues, capabilities, role scaling, stock/capacity leases, chunk checks and traffic
ownership. Add a shared ordering policy rather than a replacement scheduler.

Project priority is an integer from 0 to 100, default 50. `build priority <name>
<value>` updates it durably; status/forecast display it. Old projects without the
field behave as priority 50. A changed priority takes effect for the next
uncommitted scheduling decision, including after reboot. No task IDs, contracts,
leases or physical owners change merely because the priority changes.

Carry project lineage explicitly into production requests and their acquisition,
craft/processing, logistics and preparation/build work. Existing saved work derives
lineage only from its durable project/request links or established internal keys;
never from arbitrary worker payloads. Project-free operator work uses default 50.
Safety recovery and already journaled actions continue before ordinary new work.

Use descending project priority, then current role bottleneck preference, then
creation order/ID for deterministic task choice. Capabilities, hardware health,
equipment, dependencies, chunk availability, protected regions, fuel and ownership
remain hard admission checks. Among compatible workers, prefer the smaller
conservative mission travel/fuel budget, preserving role-specialization preference
as a tie-breaker. Unknown geometry must not beat measured feasible geometry. Keep
rescue, active access restoration and durable recovery obligations runnable.

Apply the same priority to unclaimed shared stock grants, private factory/processor
staging, production requests, exploration demand and builder supply selection.
Once stock/capacity is reserved or a worker/machine physically owns a batch, drain
that batch under its saved contract. Do not revoke claims, move staged items back,
preempt turtles or assign another worker to an owned/offline region. A lower-priority
request that has already committed physical work must still reconcile it while new
uncommitted work favors the higher-priority project. Paused or blocked high-priority
work must not prevent unrelated feasible lower-priority work from progressing.

Tests use actual queues/services and two project runtimes to prove ordering across
mining, crafting/processing, supply and construction; nearest feasible workers;
priority changes/reboots; paused/unavailable projects; shared material scarcity;
and preserved committed ownership. Native acceptance starts two separate projects
and changes priority while work is active, observes the next eligible assignment,
then independently verifies both finished structures and settled workers. Complete
one final review/consolidated corrections and full gates before integration.

Strict priority can delay lower-priority work while higher-priority demand continues.
This explicit operator policy has no hidden priority aging. Operators can change a
project's priority or pause it; fairness within equal priorities remains deterministic.

Implementation finding: shared factory graphs and acquisition targets assume one
admitted manufacturing operation. Keep concurrent request acquisition/status and
parallel lanes/workers within that operation. At finite operation boundaries, admit
the highest-priority feasible request. Derive commitments from existing workers,
journals and stock/capacity leases. Retire and replan only losing empty preferences;
revalidate unreserved inputs before creating a new factory barrier. Separate
normal scheduling generations from the repeated external-consumption retry budget.
This preserves current factory isolation without a second scheduler or owner ledger.
