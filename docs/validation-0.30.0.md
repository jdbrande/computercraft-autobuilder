# 0.30.0 fleet enrollment validation

Candidate source: `b39fc58`, on `milestone/0.30.0`. Full Lua gate is running;
this report does not claim acceptance until that gate passes.

The generated standalone `fleet.lua` discovers an enabled controller, installs
through the existing verified transaction, applies an explicit worker profile and
reboots into ordinary registration. Existing source-copy or managed workers retain
settings and checkpoints unless profile configuration is explicitly requested.
No desktop converter or local application copy is needed for the turtle bootstrap.

The single final review found four Important issues. Regression-backed corrections
preserve unmanaged worker configuration, allow software-only repair away from the
original enrollment berth, merge partial configuration objects without discarding
omitted local options, and reject unpinned discovery after early packet exhaustion.
All four reproduced before the fixes and pass afterward. Focused discovery,
enrollment, setup, installer and runtime suites pass. Python passes all18 tests;
release regeneration/check and `git diff --check` pass. Local logs are under
`/tmp/fleet-030-review-{red,green}.log` and `/tmp/fleet-030-final-python.log`.

## Native Minecraft acceptance — 2026-10-03

PrismLauncher1.20.1 world `TESTINMG`, controller237 and turtle238. The turtle at
`(1744,300,0)` started with a bootstrap script only; it fetched `fleet.lua` and every
managed worker file from the published candidate branch over real CraftOS HTTP.
The controller advertised that branch's release. Enrollment registered a healthy
building worker with verified0.30.0 software. Installation left its1,200 fuel intact.

The enrolled turtle executed a normal controller VERIFY job for the stone at
`(1746,300,0)`, reported one correct block and returned home with empty cargo and
1,188 fuel. An independent command computer confirmed the world block and turtle.
The worker's retained heading after the job was west.

An edited managed health module was then repaired by a same-version native update.
The settings file, including a local annotation, and worker checkpoint remained
byte-for-byte identical across the update. Fuel stayed1,188; after reboot normal
telemetry again reported verified software and an idle worker at home.

After the review corrections, the final source was published and the native update
was repeated. Its bootstrap downloaded the final installer, repaired software and
preserved settings/checkpoint bytes. A following `--configure` applied a profile
containing only a new supply batch size. The local supply inventory and side were
preserved, batch changed from2 to1, saved heading stayed west and fuel stayed1,188.
The rebooted worker again registered idle with verified0.30.0 software.

Both computers were shut down after the retest, and all four temporary force-load
tickets were removed; the independent cleanup receipt confirms each command.
Player position was unchanged and no world backup was made. Local fixtures,
receipts and state snapshots are under ignored `dist/live-fleet-install/`, including
`retest/result.json` and `retest/world-cleanup.json` for final-source evidence.

## Limits

Profiles require operator-declared berths/headings and real infrastructure. GPS
cannot infer heading; enrollment does not move to discover it. Unknown workers
remain telemetry-only. The native fixture exercised an explicit ID profile without
GPS; moved-location GPS checks, ambiguous/noisy discovery, interrupted profile
application and active ownership refusal are covered by automated regressions.
The Minecraft network and advertised download source must be trusted: consistency
hashes are not signatures. World chunk loading and initial controller provisioning
remain the existing configured infrastructure contracts.
