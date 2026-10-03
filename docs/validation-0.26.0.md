# 0.26.0 mission fuel forecast validation

Status: native acceptance and focused regressions passed; complete Lua gate and
ordered integration remain pending. Fuel implementation: `90fd4c0`, followed by the shared0.24 physical-detour
correction and its navigation/two-worker regressions.

## Automated evidence

Shared budget, worker telemetry, queue admission, exploration, station service,
coordination and coverage tests pass. Actual controller/worker runtime tests cover
above-low proactive refueling, controller restart, mixed-cargo home return beneath
a station chest, and worker reboot after a physical cargo deposit. The Python suite
passed all18 tests. Release generation, release verification and whitespace checks
passed. The final complete Lua suite is running; no complete pass is claimed yet.

The single final review and consolidated fix pass addressed five Important issues:
fixed miners lacked worker-specific entry geometry, small native tanks could hide a
capable alternative, blocked factory work could mask ready movement, exploration
fuel demand was invisible before trip creation, and depot returns could collide
with an overhead station chest. Each has a regression that failed before its fix.
A final departure-policy check also reproduced a worker requiring1,000 fuel after
controller admission with200. Validated departure-target telemetry and initial/
prospective budgets now prevent that mismatch without charging active trips for a
new departure. Optional telemetry remains compatible with older workers.

## Native Minecraft acceptance — 2026-10-03

The local PrismLauncher1.20.1 `TESTINMG` world used Forge47.4.10,
CC:Tweaked1.120.0 and Advanced Peripherals0.7.48r. Controller223 and builder224
operated near `(1280,300,0)`. The worker had a diamond pickaxe, wireless modem and
100 finite starting fuel. Managed fuel settings were low80, target160 and reserve100.
Eight operator-loaded chunks covered the fixture. Central storage began with eight
coal and the overhead fuel station was empty. A stone block at `(1310,300,0)` was
staged for verification; this trial does not claim construction from raw resources.
No world backup was created.

The first queued VERIFY required174 fuel despite the worker being above its low
threshold. The controller stocked the station and assigned REFUEL before VERIFY.
One coal raised fuel from100 to180. Verification reported one correct block. Its
subsequent home return exposed the overhead-chest collision, reproduced in the
actual-runtime regression. Shared depot travel now uses the existing station side
approach. The fixture also had a wired cable occupying that approach; the operator
moved the cable to a connected bypass without adding fuel or building material.
After updating and rebooting both computers, an explicit resume recovered that
already-blocked return. This operator-assisted recovery is separate from the clean
retest below. An attempted world `computercraft reboot` command was rejected;
actual reboots used the existing audit harness's REBOOT command.

With the fix installed, `forecast_retest` began at106 fuel, still above low80. The
same174-fuel requirement triggered another automatic refuel before dispatch. The
controller was restarted while the worker was traveling on VERIFY. It retained the
job, verified one correct stone block, and automatically returned beneath its fuel
station without a resume command. Final state: both projects verified, all nine
associated station/refuel/verification/home jobs completed, no supply lease, empty
worker cargo, home pose `(1280,300,0,east)` and114 fuel.

Independent command-computer reads confirmed the stone, four coal in central
storage, two coal in the station, empty turtle inventory and114 fuel. The eight
initial coal reconcile as six stored plus two consumed. The final mining-only
telemetry/budget correction was then deployed; both computers rebooted idle with
these results retained. No additional fuel or work was introduced by that update.

Audit evidence, source hashes, snapshots, setup and cleanup commands are retained
under ignored `dist/live-fuel-forecast/`. The fixture computers were shut down and
the eight force-load tickets removed after acceptance. The rig remains inspectable.
Workers used real turtle, peripheral and rednet APIs; commands entered through the
existing event-handler audit harness. This is not a terminal-input reliability test.

## Scope

Budgets describe owned or next compatible bounded excursions. They are not exact
whole-project fuel predictions for unknown terrain. Actual navigation still checks
reserves as geometry changes. Native acceptance covers a builder verification and
home return; the other roles, missing geometry, tank limits, departure policy and
prospective exploration are regression-tested. Automatic chunk deployment and
whole-project material supply forecasting remain separate fleet work.
