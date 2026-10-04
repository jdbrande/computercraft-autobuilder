# 0.36.0 project priorities acceptance candidate

Final implementation42b2a62. The repeated complete Lua gate is running; this
candidate is not accepted until that gate and release checks pass.

## Automated evidence

The20 Python tests passed. Focused production/logistics suites and the physical
streaming overlap case passed after the final-gate correction. The first full run
passed997/998 Lua tests and exposed a finite supply handoff regression.

Priorities persist per project, propagate through linked production and shared
acquisition, and order feasible uncommitted work. Existing worker, stock and
machine ownership drains under its original contract. Assignment distance breaks
ties without overriding priority or feasibility. The single final review corrected
unavailable-crafter blocking, shared mining consumers after project pause, and
metadata-only factory operation transitions allowing lower priorities to win.

The full-run failure showed that advancing multiple requests could create a new
factory barrier immediately after a builder's finite supply request completed.
The correction grants an online unpaused consumer one durable offer opportunity
per supply-batch/completed-request pair before fresh equal/lower-priority factory
admission. Empty preferences retire; committed work is preserved. Actionable
station failures consume the opportunity, while pending production and transient
ownership/inventory gates do not. Regressions cover the normal runtime offer loop,
failed stations/checkpoints, restart, newer demand, priority and physical claims.

Parallel acquisition also made the old overlap fixture's later miner return too
quickly. Its second coal ore moved four blocks farther away within the existing
mining envelope. The test still requires successful placement while a real miner
is away from its depot, restart, two builders, exact material quantities and final
settlement; its original assertions were not relaxed.

## Native Minecraft — 2026-10-04

PrismLauncher1.20.1, TESTINMG, Forge47.4.10, CC:Tweaked1.120.0 and
Advanced Peripherals0.7.48r. Controller257 and builder258 used wired stock/private
supply/home chests near(2450,300,0), finite starting fuel4000, and shipped
5s heartbeat/15s registration/30s timeout settings.

Two two-stone projects shared one builder and four available stones. Alpha began
at priority20, beta80. While beta's survey was owned, alpha was raised to100.
The existing beta assignment retained its worker and contract; alpha received the
next uncommitted project work. A settled pause, controller/worker reboot and resume
preserved the owned assignment and project priorities.

Both projects reached built, each final report counting2 correct blocks. An
independent command computer inspected all4 expected stone blocks at
(2464..2465,300,0) and(2464..2465,300,8). Final state had all work settled, no supply
lease, empty worker cargo and builder258 idle at its original depot with3518 fuel.
The native trial precedes the later full-suite handoff correction; the latter has
focused runtime/full-chain evidence and is included in the repeated full gate.

Computers257/258 were shut down, their off states independently read, and all4
force-load tickets removed. No backup was made; the player was not moved. The rig
and finished blocks remain. Ignored scripts, snapshots and command receipts are
under dist/live-project-priorities/.

Priority scheduling is conservative at committed manufacturing boundaries; it does
not promise unrestricted simultaneous independent manufacturing graphs. Sustained
mixed-role load and the final combined fleet acceptance remain separate work.
