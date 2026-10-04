# 0.29.0 worker health acceptance

Accepted0.29.0, final implementation `c482afa`. The full fleet roadmap remains
unfinished. The complete Lua suite passed868 tests (`/tmp/fleet-029-final-full.log`),
all18 Python tests passed, and release generation/check plus `git diff --check`
passed. Accepted0.28 documentation was merged without changing tested source.

Hardware, telemetry and both assignment queues have targeted tests for missing
APIs, changing tools, legacy compatibility, cyclic unknown fields, malformed known
fields, repaired idle eligibility, retained owners and yielding admission checks.
Software checks cover hashes, missing code, receipt/manifest file sets, required
files, custom startup and unmanaged source copies. Native terminal detection avoids
misclassifying a turtle when its display is redirected.

The single final review found health checks occurred after private courier/crafter
stock staging; scaling could reserve a worker for a role forbidden by its hardware;
repair omitted digging checks; incomplete manifest selection could still report
verified. Regression-backed fixes check both selection and pre-ownership boundaries,
preserve existing journals, filter competing work and share installer file rules.
Actual private-crafting tests prove a healthy alternative finishes and a health
change during capacity observation creates no stock/capacity claim.

Native235/236 in TESTINMG reported advanced pickaxe and normal crafting-table
hardware using real turtle/peripheral APIs, with777 fuel before and after. A
fixture-generated receipt verified managed files, detected an intentional edit,
and verified after restoration. The unmanaged fixture reported unmanaged. These
are integrity observations, not acceptance of installation over HTTP. Computers
were shut down and their one force-load ticket removed. The same native checks
passed on final correction `c482afa`: both remained at777 fuel, the managed fixture
verified/detected the edit/restored, and the source copy remained unmanaged. Cleanup
was independently repeated and confirmed. Evidence is under ignored
`dist/live-fleet-health/` and `retest/`. The complete868-test Lua gate and18-test Python gate pass.
