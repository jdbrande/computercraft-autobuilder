# Worker equipment and software health

Requirements3.4,5 and24 need hardware evidence and current software health before
single-command onboarding can safely enable new workers. This milestone adds that
prerequisite to the existing registration/heartbeat and dispatch boundaries.
Single-command discovery/configuration/update is the following dependent task;
this report must not claim that workflow complete prematurely.

Observe hardware without moving, digging, crafting or swapping upgrades. Report
normal/advanced turtle type where detectable, equipped left/right item names,
bounded peripheral names/types, movement/crafting API availability and scanner
availability. CC:Tweaked1.116+ exposes read-only `getEquippedLeft/Right`; older APIs
report equipment unknown, rather than unequipping a modem/tool to inspect it.
Primary reference: https://tweaked.cc/module/turtle.html#getEquippedLeft .

Configured logical roles remain opt-in. Fresh known missing hardware removes new
work eligibility for the corresponding role; it never releases owned tasks, routes,
stock or recovery journals. Unknown legacy hardware stays explicitly unknown and
retains existing protocol compatibility. A restored tool can make an idle worker
eligible again through normal registration. No physical probing is authorized by
mere capability discovery.

Verify managed code against the existing installation receipt once per startup,
using existing SHA-256/path validation and cooperative execution. Report installed
version and verified/modified/unmanaged/unavailable status. Preserve the installer's
supported custom root startup and local settings/state. A known damaged managed
runtime should not receive new ordinary jobs; owned recovery stays available.
Source-copy development installations without receipts report unmanaged, never
verified. Do not download, overwrite settings, or update code from a heartbeat.

Use one bounded optional health field in the existing telemetry schema, validated
and cleaned at the network boundary. Show actionable equipment/software reasons in
worker status. Reuse worker eligibility checks instead of a second scheduler.
Tests must exercise malformed/cyclic messages, absent old APIs, missing/changed
upgrades, idle eligibility restoration, active-owner preservation, receipt edits,
missing files and no physical side effects. Native read-only equipment/software
checks are useful; full tests, one final review/fix pass and release evidence follow.
