# Milestone 1 validation record

Scope: only the first milestone of the attached request. No Minecraft instance was
available, so live acceptance remains explicitly unverified. The checklist is in README.

## Decisions

- Kept files directly in the requested empty workspace; there was no Git repository
  or shared branch to isolate, commit, or merge.
- Used configured controller ID with periodic registration instead of leader election.
- Diagnostic logging is `core/log.lua`; future tree harvesting owns `resources/logger.lua`.
- Future milestone directories contain scope notes, not placeholder implementations.
- GPS polling uses a separate CraftOS parallel coroutine. The event-loop test injects
  an ACK and timer while GPS is waiting for a modem event; heartbeats continue.
- Normal snapshot recovery preserves position. Backup recovery invalidates heading
  and position until checked because a backup may predate movement intent.
- Boot generation combines the saved generation and UTC milliseconds. Assumes the
  server clock is not rolled back together with restored historical state.
- Heading calibration derives facing from two operator-supplied adjacent GPS fixes;
  startup never moves a turtle to discover its heading. Explicit `pose.lua` confirms
  a known pose without moving it.
- Navigation stops at obstacles and never digs. A*, dynamic reservations, jobs and
  movement clients remain future work; no unsafe imitation of them is supplied.

## Development checks

Tests were written and run before their modules were implemented; the initial runs
failed due to absent modules, then passed with the implementation. Hardware is isolated
at filesystem, turtle, modem, GPS and event APIs. The test serializer is a desktop
fixture; live serialization uses CC:Tweaked's `textutils` implementation.

An independent code reviewer inspected the full first implementation and ran its
then-current 18 tests. Both actionable findings were reproduced and fixed:

- Backup recovery could preserve pre-turn heading: added explicit invalidation and
  operator pose confirmation, with a regression test.
- Configuration accepted labels/capabilities rejected by the wire protocol: shared
  string validation and aligned count/length rules, with a regression test.

Additional reproduced and fixed issues:

- Full duplicate cache evicted a duplicate before checking it.
- Recovered backup reused a boot counter generation.
- Truncated log messages lost their trailing newline.
- Facing the already-recorded direction reported success despite an uncertain pose.

All fixes include tests which failed before the correction. Final verification:

- `.venv/bin/python tests/run.py`: 29 tests passed.
- Lua 5.2 `load` syntax check: all 22 Lua source/test/launcher files passed.

No unresolved review findings were deferred.

## Live limitations

Actual CC:Tweaked peripheral/event behavior, Minecraft saves and chunk loading need
in-game acceptance. The test scheduler models CraftOS event broadcasting; it is not
CraftOS itself. The demo has no authentication, automatic fueling, mining, crafting,
building, import, region coordination or job execution. Manual moves outside the
navigation API require explicit pose confirmation. Filesystem-level corruption of
both checkpoint generations intentionally stops startup.
