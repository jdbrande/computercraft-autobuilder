# Persistent mining intelligence

Requirement10 extends the accepted exploration controller; it does not introduce
another scheduler. Miners must learn from inspection-only trips as well as scanner
trips. The controller must remember useful resources, hazardous/inaccessible cells,
confirmed travel, successful sectors and exhaustion across restarts, and use that
information to choose safer promising work. Requirement44 allocation remains the
consumer of measured delivery rates. This milestone does not change stock ownership.

## Evidence and authority

Reuse exploration sector records and their bounded survey/observation lists.
Keep existing searched-cell coverage, protection configuration and immutable trip
geometry. Add optional bounded physical evidence to exploration progress, cleaned
and validated by the existing mining protocol. Older reports remain valid.

Each trip may retain at most64 evidence entries. Each entry contains integer world
coordinates, a kind (`clear`, `liquid`, `blocked`, `protected`), optional block name
and a reason of at most128 characters. Deduplicate by coordinate; a later confirmed
clear observation supersedes a prior local obstruction. Persist observations before
advancing the survey or abandoning a route. Never mark a movement as clear before
its physical success has been reconciled through the existing move journal.

Keep up to64 named resource observations per sector, including inspection sightings.
These are historical hints, not current block-state certificates. Derive an observed
material-density estimate from retained matching sightings and searched coverage;
record actual delivered yield and successful trip counts separately. Empty trips
must not invent resources. Preserve a bounded sector evidence list, terminal trip
result/reason, and successful/exhausted summaries. Exactly duplicated terminal
reports must not add yield or success counters again.

Validate every evidence coordinate against the assigned sector, authorized route
or exit before merging it. Do not accept arbitrary remote coordinates, unknown
kinds, oversized lists, sparse arrays or malformed quantities. Ownership and current
worker generation remain prerequisites. A failed root checkpoint must not silently
retire an unrecorded trip or double its counters on retry.

## Selection and routes

Prefer non-exhausted sectors with retained evidence of the requested material;
compare observed density and confirmed prior delivery before stable travel-distance
and existing height/coordinate tie breaks. Hazard evidence lowers a candidate's
priority without converting it into an unbounded global search.

Use retained confirmed liquid/blocker cells to avoid known bad route steps within
the existing256-node planner budget. Protected cells still come from the current
registered protection volumes. Confirmed tunnels improve route preference only;
every move and dig continues to inspect, request grants and obey current coverage,
protection, fuel and ownership. An old clear cell never authorizes blind excavation.
Temporary turtle reservations must not become permanent geological hazards.

Distinguish inaccessible results from observed resource exhaustion in diagnostics.
Keep current conservative no-repeat behavior for a completed blocked attempt until
an explicit retry or a changed search envelope makes new work possible. A retry may
clear stale negative evidence only for an unowned sector; it cannot revoke an active
trip, clear physical-action journals or reset another worker's route.

## Operator view and scope

Extend the existing exploration commands/status with sector evidence counts, observed
density, delivered yield and exact blocking coordinates/reasons. Provide an explicit
sector retry through the existing controller command path. Preserve task identities,
old checkpoints and bounded report sizes. No dependencies or new world-scanning API.

Out of scope for this milestone: new resource provider hardware, global terrain maps,
automatic infrastructure deployment, inventory rescue and continuous project supply
forecasting. These remain required later work in the progress ledger.

## Acceptance

Tests must cover inspection and scanner evidence, liquids/waterlogged blocks, protected
and blocked paths, successful reconciled moves, failed/ambiguous digs, malformed and
out-of-contract messages, bounded retention, idempotent terminal reports, checkpoint
failure/restart, density/yield ranking and preserved ownership during retries. Actual
controller/miner runtime tests must select useful work after empty/hazardous sectors
without counting predicted drops or bypassing a denied mutation.

Run a native inspection-only acquisition with staged hazards and alternative reachable
resources, reboot while safely between physical actions, and independently reconcile
actual deliveries and retained terrain. Report fixture loading/fuel/source assumptions.
One final whole-branch review/fix pass, full Lua/Python/release gates and integration
follow before continuing the remaining fleet requirements.
