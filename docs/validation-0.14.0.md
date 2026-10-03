# Inventory ownership acceptance — 0.14.0

## Implemented boundary

Durable item-count claims now gate new furnace and crafting jobs. Measured
withdrawal/output receipts update reservations; restart retains ownership.
`resource ITEM` separates physical, available, reserved, transit, expected and
active-request demand. Offline claims do not expire. The global factory execution
barrier remains; count claims alone do not enable safe parallel chest mutation.

Five ledger tests cover atomic competing contracts, immutable duplicate IDs,
ordered partial receipts, malformed counts, restart, release/cancel guards,
unknown stock and failed/throwing saves. Runtime regressions cover ungranted
hardware/assignment prevention, shortage recovery, partial Crafty receipts across
controller/worker reboot, protocol validation and exact status values. Existing
crashed furnace-lane and whole-chain recovery tests continue to pass.

Final initial gate: 430 Lua tests and all 16 Python tests passed; generated 0.14.0
release artifacts and `tools/release.py --check` passed. Whole-branch review follows
this gate; any review fixes and rerun evidence are appended below.

## Live Minecraft — 2026-10-03

Reused controller 100, furnace 507 and Crafty 105 in TESTINMG. Both computers were
updated with current source while preserving settings and journals. The operator
loaded the small test envelope and prepared four cobblestone and one coal in the
depot chest. Six stone bricks remained from the preceding acceptance. These raw
inputs were staged to test factory reservations; this trial does not claim mining
or automatic fuel sourcing.

`request minecraft:stone_bricks 10` granted a furnace contract for four cobblestone
and one coal, with four stone expected. Live snapshots recorded the claim held
through partial output delivery, then released after four stone were delivered.
Crafty received a four-stone input contract and delivered four bricks. Its saved
claim recorded four withdrawn stone and four delivered bricks before release.
Both claims ended released, and the request completed with ten physical bricks.

A controller reboot preserved both released claims. The resource command reported
`stock=10 available=10 reserved=0 transit=0 expected=0 demand=0`. Independent command
computer inspection of the actual depot chest confirmed ten stone bricks. Test
computers were shut down and test force-load tickets removed. Local snapshots,
raw receipt observations and independent inspection are in `dist/live-inventory/`.

## Limits

- Shared inventory counts cover configured stock inventories; machine contents
  are tracked through production receipts, not credited as available stock.
- Transit accounting exists in the ledger; courier pickup/capacity grants and
  automatic fuel distribution/rescue remain subsequent integration work.
- Factory isolation remains mandatory until independent station staging and
  suitable transfer journals are implemented. Destination capacity is not yet
  reserved by this count ledger.
- Saved legacy jobs retain the exclusive path. Old workers without partial
  receipts hold conservative claims until exact-output completion acknowledgement.
- External inventory mutation can create a shortfall; the system blocks and keeps
  ownership rather than inventing stock or silently abandoning a worker.
