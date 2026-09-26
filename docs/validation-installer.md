# Installer and update validation

Scope: deploy the implemented Milestone 2 application; retain explicit foundation
status for builder/logger/courier profiles. No future task engines were fabricated.

Tests added before implementation covered SHA-256 vectors, manifest path/URL and
role validation, staging, interrupted promotion, repeatable rollback, configuration
preservation, startup adoption, update/repair/version behavior and disabled HTTP.
Desktop tests cover all six offline profiles, refusing existing output directories,
release hash consistency, selected-role dependency closure and deterministic generation.

The standalone bootstrap is executed in Lua 5.2 with real JSON serialization and
without access to installed project modules. A subsequent update runs through that
same bundle. Failure injection deletes the active installer and interrupts rollback;
the independently bundled recovery script then restores it with HTTP disabled.

Independent review found two deployment issues, each reproduced before correction:

- Replacing the installer could temporarily remove its own recovery entry point.
  Transactions now retain a separate verified standalone recovery executable.
- An extensionless `/startup` could shadow `/startup.lua`. Installation now refuses
  that conflict before downloads or modifications, with migration instructions.

Other checks confirm binary filesystem handles preserve exact downloaded bytes,
edited defaults cause an error instead of being overwritten, and all application
entry points stop while an install transaction exists. Hashing yields to CraftOS
between files and during large files to avoid CPU-only execution timeouts.

Final verification (2026-09-26):

- `.venv/bin/python tests/run.py`: **85 tests passed**.
- `.venv/bin/python -m unittest discover -s tests -p test_release.py -v`: **4 tests passed**.
- `python3 tools/release.py --check`: generated artifacts match current sources.
- Lua 5.2 `load` syntax check: **46 source, test and bundled Lua files passed**.
- `dist/controller/`: regenerated from the final release and all managed hashes verified.
- Review follow-up confirmed both deployment findings resolved, with no remaining blocking findings.

Live Minecraft peripherals, HTTP policy, actual GitHub publication and world-save
durability are not simulated by these desktop checks; see the in-game acceptance
steps in the installation guide and the Milestone 2 guide.
