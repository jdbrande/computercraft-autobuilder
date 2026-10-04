# Registered inventory processors

Requirements4.4 and16 extend existing furnace lanes to registered non-crafting
machines. Keep existing furnace jobs and journals unchanged. Add a PROCESS provider
and finite operation using the same dependency planner, stock/capacity ledgers,
factory exclusion and measured transfer journal. Do not emulate unavailable machine
APIs or make arbitrary peripheral method calls supplied by configuration.

Register machines by inventory peripheral name and recipes by output item. A recipe
specifies exact input item counts/slots, output slot/yield, optional item fuel with
batches-per-fuel ratio, compatible machine IDs and estimated seconds per batch.
Configuration is bounded plain data. A process recipe may explicitly override the
normal recipe for that output, so blast furnaces or modded transformations can be
selected without mutating the global recipe registry. Existing craft/smelt behavior
remains the default. Vanilla stonecutters without an automatable inventory must be
reported unsupported; ordinary equivalent crafting recipes still work.

Split demand into finite capacity-fitting batches across compatible idle machines.
Reserve shared ingredients, whole private machine inventory and destination capacity
before loading. Machine inventories must start empty; residual native burn energy is
not physical stock. Inputs may transform autonomously, so journal transfers against
the exclusively observed source/destination storage endpoint, as furnace execution
already does. Never infer output delivery from elapsed time or disappeared inputs.
Validate recipe/slot identity across restart and retain machine ownership until exact
outputs and unused item fuel return to storage. Unexpected items, disconnects and
ambiguous observations block the same owner rather than duplicating a batch.

Register energy-consuming modded machines through the inventory contract when their
power/activation infrastructure is already configured. Report stalls and expected
time honestly; the fleet does not fabricate energy or simulate an external machine.
Native acceptance can use real blast furnace/smoker inventories. Simulation should
include a multi-input higher-yield powered processor, disjoint concurrent machines,
capacity-limited batches, partial transfers, interruption after side effects, paused
recovery, missing power/output, changed configuration and final item conservation.
One final review/consolidated fixes, full gates and permanent evidence precede
integration, then renewable provider/reserve coverage continues.

Implementation refinement: keep a finite job's stock claim, but stream one complete
recipe batch at a time through the exclusively owned machine. Before loading each
batch, reserve only that batch's destination capacity; release that tranche only
after measured output delivery. This avoids assuming an unseen output stack limit
or requiring an entire64-batch job to fit simultaneously in output storage. The
machine lease remains held between tranches. Observed surplus item fuel receives
its own destination-capacity tranche and measured `fuelReturned` journal counter.
It is not promised output and does not alter the stock lease's exact product-output
contract: withdrawn fuel remains gross withdrawal, while physically returned fuel
reappears in the next ordinary stock observation. Never infer residual burn as fuel.
