# Persistent mining intelligence

Exploration now retains what miners actually observe. Inspection-only miners and
scanner miners report resource sightings, liquid and waterlogged obstacles,
protected blocks, failed digs and confirmed travel. A move becomes a clear cell
only after its physical journal reconciles successfully. Temporary movement grants
and turtle traffic are not geological hazards. A physically inspected turtle
waits through the normal reservation/retry path without exhausting its sector.

Each trip and sector retains at most64 named sightings and64 physical evidence
cells. Repeated coordinates replace older evidence in that record. Unresolved hazards
retain priority over clear travel when the64-cell bound is reached. Sector history
also keeps per-material delivered quantities, attributed mined quantities, successful trips, empty searches and
inaccessible trips. Completed-message duplicates do not add these counters again;
failed controller saves roll back the trip, acquisition and sector together. Initial
depot cargo remains a valid acquisition receipt but does not establish a successful
mining location. Reports without the new initial-cargo counter conservatively add
no attributed mined yield; older unclassified success counts reset on their next
sector update. Total delivered receipts remain intact.

Candidates with evidence of the requested material come first. Within that group,
the controller compares observed density, average attributed mined yield and hazard count,
then uses travel distance and stable height/coordinate ordering. Density is retained
matching sightings divided by the larger of sightings or searched cells. It is a
bounded historical estimate, not a measurement of unmined reserves. Exhausted or
inaccessible attempts stay excluded until the search envelope changes or an operator
explicitly retries their sector.

Planning avoids retained negative cells and prefers confirmed clear steps on direct
routes. Current bounds, infrastructure protection, active ownership, fuel and loaded
coverage remain authoritative. Historical clear cells never authorize excavation;
workers still inspect and obtain fresh movement and mutation grants. Conflicting
records conservatively retain a hazard until its reporting sector is retried.

Use these controller commands:

- `exploration status`: active groups and trips.
- `exploration sector <id>`: sightings, density, searched cells, actual delivery,
  trip outcomes and exact evidence coordinates/reasons. Use Shift N/P to page.
- `exploration retry <id>`: permit a new search of an unowned sector, resetting its
  searched/exhausted coverage and negative evidence while retaining sightings,
  confirmed travel and delivery history.

Retry refuses sectors or routes held by any unfinished miner, including an offline
owner. It does not clear physical journals, transfer ownership or erase delivered
stock. If a stale hazard was reported by several sectors, their retained evidence
can be inspected and retried separately after their owners have settled.

Evidence is optional on existing progress messages, so older workers can continue
to participate. They do not provide the new evidence until their software is updated.
No scanner, new peripheral, external service or dependency is required.
