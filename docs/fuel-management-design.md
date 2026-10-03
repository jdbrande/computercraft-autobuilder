# Fleet fuel management

Implements fleet requirements 11 and 25, using the inventory ledger and existing
worker/task/navigation boundaries. Preserve native turtle actions and measured
receipts. No new scheduler, operating-system automation or operator commands in
product execution.

## Policy and budgeting

Add a validated `fuel` configuration with enabled flag, preferred item, per-item
energy estimates, returned-container mapping, low threshold, target and dedicated
stations. Defaults cover coal, charcoal, coal blocks and lava buckets. Estimates
plan deliveries; actual `getFuelLevel` determines whether a turtle is ready.
Every mission budget records outward, work, return and reserve costs. Unknown pose
or insufficient fuel denies dispatch; a worker may receive fuel work first.

Reserved slot 15 remains the normal fuel slot and slot 16 remains equipment.
Refueling never burns arbitrary build inventory. Configured returned containers
remain in slot 15 until safely deposited in a verified depot container; no world
drops. Custom fuel values are estimates and never override actual refuel failures.

Native API basis: [turtle refuel](https://tweaked.cc/module/turtle.html#refuel)
consumes selected-slot fuel and exposes measured energy/capacity. Wired inventory
transfers use [inventory methods](https://tweaked.cc/generic_peripheral/inventory.html).
The installed CC:Tweaked is 1.120.0; the newer turtle_storage upgrade API is not
required (official docs introduce it in 1.121.0).

## Station distribution

A station identifies a wired fuel chest, the worker stand below it, its item and
stock target. Fuel chests are dedicated to this service and cannot also be shared
factory stock or another station. Claim exact source fuel before transfer; reserve
the receiving chest while filling it. Use observed transfers and durable journals.
Only grant a worker its REFUEL job after station filling has reconciled. Pending
managed refuel work prevents a mining job from taking that worker first.

Use the production service's inventory operation lock for controller transfers.
Do not race factory journals or let a worker consume the receiving chest during a
fill. Fuel-purpose claims may use the configured turtle fuel reserve; factory
claims still protect it. Missing fuel queues ordinary resource production, using
coal exploration or the existing charcoal recipe/tree provider. Surface bootstrap
shortages honestly when no fueled producer or stored fuel is available.

## Rescue

A stranded worker retains its original task and pose journal. A bounded recovery
handshake freezes it at a confirmed pose before a courier is assigned. The courier
reserves a fuel pickup, carries a finite quantity, approaches through ordinary
navigation/protection/reservations, verifies the receiving turtle, and reports
actual transfer. The receiver confirms delivery before consuming the granted fuel
and resumes only a known fuel-blocked task. Unknown motion remains a recovery stop.

Delivery to a turtle must preserve world-drop prevention and available capacity.
Prefer native adjacent inventory transfer; if the installed environment cannot
identify the target safely, use a verified temporary station with explicit block
ownership. Do not assume a newer turtle-storage API. Courier fuel must cover pickup,
delivery, return and reserve. Offline rescue owners keep their claims. A partial
or delayed receipt must never create duplicate fuel or duplicate rescue missions.

## Acceptance and limits

Test malformed policies, finite budgets, custom fuel, lava-container retention,
low-fuel dispatch exclusion, station shortage/refill, partial transfers, reboot,
full inventories and offline owners. Run a native unfueled-depot and stranded
worker rescue acceptance with finite courier fuel. Keep the loaded test envelope
explicit until the chunk-loading milestone. A complete rescue returns the courier
and releases claims; a blocked path remains actionable without excavating protected
or unknown terrain merely to reach a turtle.

## Native rescue transfer probe

On 2026-10-03, a temporary advanced turtle107 above idle miner101 read the
adjacent peripheral type `turtle`, called `getID` and obtained101, inspected the
actual turtle block, then transferred one coal with `dropDown`. Its own inventory
count changed from1 to0. This establishes that the installed1.120 environment
supports identity-checked native delivery; no temporary-chest or new upgrade API
is needed. The probe coal/block were cleaned up. Production rescue still requires
the frozen-target handshake, capacity and delivery/consumption receipts. Evidence:
ignored `dist/live-fuel/adjacent-transfer-probe.json`.
