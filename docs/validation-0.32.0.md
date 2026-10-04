# 0.32.0 registered renewable providers acceptance

Accepted0.32.0, final implementation `a01825b`: all923 Lua tests and all18 Python
tests passed. Release generation/check and `git diff --check` passed. Accepted0.31
documentation was merged with tested source, tests, tools and release artifacts
unchanged. The complete fleet roadmap remains in progress.

The existing renewable actor now consumes bounded data definitions for crops and
base-preserving columns. Native wheat, carrots, potatoes and beetroot use their
actual maturity states. Saved assignments retain their selected definitions and
planting reserves across configuration changes and restart. New contracts require
updated worker capabilities; health checks include placement when replanting.

The single final review found four Important issues and one Minor issue. Red/green
regressions cover controller authorization of frozen adapters and new geometry,
same-identifier crop/seed maturity, provider fallback between farm contracts,
placement health admission and a pending planting item excluded from cargo
forecasts. Actual queue/protection tests preserve soil, column bases, configured
territory and exclusive ownership after registry edits and restart. Retirement
checks preserve assigned/offline/journaled/shared demand and roll back failed saves.

## Native Minecraft acceptance — 2026-10-03

PrismLauncher1.20.1 `TESTINMG`, controller241 and farmer242, two carrot plots at
`(1868,300,0)` and `(1870,300,0)`. The farmer began with2,000 finite fuel and two
carrots for replanting. Managed storage began empty. Operator commands supplied
mature crops, farmland and water; the worker used real turtle/rednet APIs.

The first candidate could not obtain mutation grants because the controller did
not recognize its frozen farm definition. Its owner was retained through the fix.
The resumed actor harvested four carrots and survived controller/worker restart,
then its soil inspection descended into the empty crop cell. The solid turtle
converted farmland underneath to dirt. Independent world inspection confirmed the
first soil was dirt while the second remained farmland and irrigation remained.
A regression models this real block behavior. Crop planting now stays above the
cell and relies on native seed placement to validate farmland. Tree soil checks
remain. Failed native placement retains the owned task and cargo.

The first task completed after the operator restored only the soil damaged by the
pre-fix inspection. It deposited three carrots, retained two planting carrots and
returned home. This assisted first run is not the clean final-source acceptance.

A second request increased physical stock demand from2 to4. With three carrots
already stored, the final-source farmer skipped the immature first crop, harvested
the untouched second plot, survived another controller/worker restart, replanted
and delivered four more carrots. Both requests and both jobs completed. Independent
inspection confirmed both crops replanted, both farmland blocks intact, seven
carrots in the chest and exactly two carrots retained by the idle farmer at home.
Final fuel was1,942. No soil repair or finished resources were supplied during this
second run. No growth was credited before physical harvest and measured deposit.

Both computers were shut down and all four temporary force-load tickets removed;
the independent receipt confirms every check and cleanup command. Player position
was unchanged and no world backup was made. Local audit evidence is under ignored
`dist/live-renewables/`, especially `soil-failure-world.json`,
`first-completed-world.json` and `untouched-retest/`.

## Limits

Registered crops require native plantable items and substrates. Natural growth,
light and terrain remain physical preconditions; immature plots wait rather than
fabricating yield. Custom executable adapters and arbitrary tree structures are not
accepted by this bounded data contract. Planting reserves belong to the active farm
contract, not a permanent global inventory policy across unrelated worker roles.
The native test covers carrots; other crop ages, custom definitions and retained
column bases are exercised by actor simulations. No native arbitrary modded crop
compatibility is claimed.
