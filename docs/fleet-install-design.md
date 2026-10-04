# Fleet installation and enrollment

Requirement5 needs one command joining existing discovery, installation integrity,
configuration and registration. Implement `fleet install` as a generated standalone
bootstrap using the existing installer transaction. `wget run .../fleet.lua install`
works before software exists; an installed `fleet` shell alias uses the same entry.
Do not add another downloader, package format, update journal or worker scheduler.

Controllers opt into enrollment and provide explicit worker profiles. A profile
is ordinary validated worker configuration, keyed by computer ID or selected by a
configured berth position matched with GPS. A berth also declares its expected
heading: the operator places the turtle facing that direction. Discovery never
moves a turtle to infer heading. A worker without a matching configured profile
can register telemetry but remains unavailable for physical work until configured;
unknown pose or missing infrastructure cannot be guessed into an operational role.

Discovery uses a fixed versioned rednet protocol and bounded nonce-bound replies.
One enabled controller is selected automatically; multiple offers require an
explicit controller ID, rather than silently choosing a different fleet. Existing
installations retain their controller and settings. Controller profiles are data,
not executable Lua. Validate bounded acyclic values and the ordinary Config schema
before saving. Local data/log paths remain local, and profiles cannot clear saved
ownership, change identity, or bypass interrupted-pose recovery.

The bootstrap discovers a controller, installs/repairs the advertised current
release with the existing transactional manager, then applies a validated profile
through the existing setup persistence rules. Source overrides are explicit and
manifest hashes/role checks still apply. Local settings on established workers are
preserved by default; fleet profile refresh is an explicit idle-only operation.
Reboot into normal registration/health reporting. Active workers must drain before
updates; enrollment is never a remote code-write heartbeat handler.

Native acceptance should use real rednet discovery and a local HTTP release server
(or published source when appropriate), preserving finite fuel and settings/state.
Tests cover malformed/duplicate/ambiguous discovery, absent profiles, changed source,
interrupted installer recovery, settings preservation, active ownership rejection,
and post-install registration. Native fixtures with generated receipts from0.29
are not installer acceptance. One final review/fix pass and complete release gates
precede ordered integration.
