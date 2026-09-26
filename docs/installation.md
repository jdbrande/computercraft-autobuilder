# Installation, updates and offline deployment

Release **0.10.2** packages resource acquisition, production, schematic projects,
construction/verification/repair, managed renewables and logistics. Python is needed only
on the desktop when preparing releases or offline folders. Computers and turtles
use CC:Tweaked's Lua, HTTP, filesystem and JSON APIs with no downloaded libraries.

## Roles

| Profile | Device | Current behavior |
| --- | --- | --- |
| `controller` | Advanced Computer with modem | Registry, production, project scheduling, resource inventory and mining jobs |
| `worker` | Advanced Turtle with modem | Telemetry; task capabilities configured explicitly |
| `miner` | Advanced Turtle with modem | Worker with mining setup guidance |
| `builder` | Advanced Turtle with modem | New installs enable building, verification and repair capability |
| `logger` | Advanced Turtle with modem | New installs enable managed tree harvesting capability |
| `courier` | Advanced Turtle with modem | New installs enable chest-to-chest transport capability |

The deployment profile is stored in the installation receipt. All turtle profiles
use the `worker` runtime. No profile automatically enables mining. Follow
[the mining guide](milestone-2.md) to configure pickaxe/scanner, GPS/heading, protected
areas, depot, fuel and bounded mining. Installation does not move the turtle.

Fresh builder/logger/courier settings contain `automation={building=true}`,
`automation={logging=true}`, or `automation={courier=true}` respectively. They still
need an actual pose, depot, fuel and their role hardware before work is assigned.
Updates preserve old settings byte-for-byte: enable these capabilities manually on
existing installations. Crafty station workers use `automation={crafting=true}`;
managed crop workers use `automation={farming=true}`. Configure those on the generic
worker profile, with the hardware in the focused guides.

Start with the [main setup and command guide](../README.md), then follow
[production](production.md), [blueprints](blueprints.md),
[construction](construction.md), [logistics](logistics.md) or
[renewables](renewables.md) for your roles.

## Publish your GitHub source

1. The published source is [jdbrande/computercraft-autobuilder](https://github.com/jdbrande/computercraft-autobuilder).
   To host your own fork, create a repository and place the project at its root.
2. In the desktop project directory, set the raw repository URL:

   ```sh
   python3 tools/release.py --base https://raw.githubusercontent.com/USERNAME/REPOSITORY/main --version 0.10.2
   ```

3. Commit/publish the application sources together with generated `installer.lua`
   and `manifest.json`, root `startup.lua` and `update.lua`. Publish a complete
   release in one Git commit. Do not publish local settings containing personal
   configuration, saved world state or logs.
4. Before subsequent releases, change the numeric `major.minor.patch` version and
   regenerate. Check generated files with `python3 tools/release.py --check`.

The generator bundles `autobuilder/install/*.lua` into a standalone installer with
a private module loader. Edit those source modules, then regenerate; edits to the
generated installer are replaced. To change the base URL, use `--base` again; the
generator updates both the embedded URL and every manifest URL. Without arguments
it retains the current manifest's URL and version.

`main` tracks future releases. A tag or commit SHA can be used instead when pinning
a release; an installation pinned to a commit stays there until you change its
source with `update --base NEW_RAW_DIRECTORY`. Changing source intentionally
rebases manifest file paths onto that source; remote file URLs still undergo
manifest validation. Only use a source you trust. Checksums detect corruption and
inconsistent publication; they are not digital signatures.

## Online installation

Run `id` on the controller and note the numeric ID. Enable HTTP in the server's
CC:Tweaked configuration and permit HTTPS access to `raw.githubusercontent.com`.
Stop any existing Autobuilder program with **Q** and close other running copies
before installing or updating. Run only one installer/update at a time.

Controller:

```text
wget run https://raw.githubusercontent.com/USERNAME/REPOSITORY/main/installer.lua controller
```

Worker, prompting for the controller ID:

```text
wget run https://raw.githubusercontent.com/USERNAME/REPOSITORY/main/installer.lua worker
```

Miner, with an explicit controller ID of `7`:

```text
wget run https://raw.githubusercontent.com/USERNAME/REPOSITORY/main/installer.lua miner 7
```

Replace the placeholders before running these commands. `--controller 7` is also
accepted. Append `--reboot` to reboot automatically; otherwise the installer prints
`Run reboot`. Configure your local settings and role hardware before assigning work; mining remains opt-in.

The CC:Tweaked 1.20.x [wget implementation](https://github.com/cc-tweaked/CC-Tweaked/blob/mc-1.20.x/projects/core/src/main/resources/data/computercraft/lua/rom/programs/http/wget.lua)
supports `wget run URL arguments...`. If you prefer saving the bootstrap first, use
a fresh filename so that a failed initial download cannot replace an installed one:

```text
wget https://raw.githubusercontent.com/USERNAME/REPOSITORY/main/installer.lua /bootstrap-new.lua
/bootstrap-new.lua controller
```

The completed installation supplies `/installer.lua`, so these also work from `/`:

```text
installer controller
installer worker 7
```

These are alternatives for different computers, not commands to switch a running
computer's role. Existing installations refuse role changes automatically.

If you fork the default checkout without regenerating it, pass your source explicitly:

```text
wget run https://raw.githubusercontent.com/USERNAME/REPOSITORY/main/installer.lua worker 7 --base https://raw.githubusercontent.com/USERNAME/REPOSITORY/main
```

This override is recorded for future updates. The embedded placeholder URL is
otherwise rejected with a setup message.

## Files and local configuration

The directory structure is preserved, for example:

```text
/installer.lua
/update.lua
/startup.lua
/manifest.json
/autobuilder/.installation.json
/autobuilder/settings.lua           # local values; never in the download manifest
/autobuilder/config.lua             # managed defaults and validation
/autobuilder/startup.lua
/autobuilder/core/navigation.lua
/autobuilder/core/gps.lua
/autobuilder/core/network.lua
/autobuilder/core/checkpoint.lua
/autobuilder/workers/worker.lua     # turtle profiles
```

The manifest lists each managed file's relative path, remote URL, role requirements,
version, byte length and SHA-256 checksum. Shared runtime dependencies are included
in every profile that needs them. The manifest does not include itself or local
settings, avoiding a recursive checksum or configuration replacement.

Normal updates preserve `settings.lua` byte-for-byte and never run it. Checkpoints
under `autobuilder/data/` and files under `autobuilder/logs/` are outside installer
ownership. Do not put local values in `config.lua`: if it has local modifications,
the update stops before replacing working files. Move those values to `settings.lua`
and restore the matching original defaults before retrying.

On first adoption of a manual installation, existing settings must return a plain
table with the correct runtime role and controller ID. A supplied controller ID
must match; the installer will not silently alter it. Existing unmanaged defaults
must match the release or be migrated explicitly. A missing settings file on an
already installed computer is an error requiring restoration, not a reason to
silently generate new settings.

An extensionless `/startup`, `/installer` or `/update` would shadow the generated
`.lua` file. Installation stops before downloading; back up and rename that
conflicting file/directory explicitly, then retry.

On first install, a different existing `/startup.lua` is saved as
`/startup.pre-autobuilder.lua`; an unrelated existing backup is never overwritten.
Updates preserve an edited root startup. If you customize startup, retain its
transaction guard and call `/autobuilder/startup.lua` once. Each application entry
point also checks for pending installation recovery before loading application code.

## Updates and interrupted installations

Stop the application with **Q**, then:

```text
cd /
update
reboot
```

Or run `/update.lua` from any directory. `update --reboot` reboots automatically.
The updater reads the installed receipt, retrieves the remote manifest, refuses
older versions, and hashes local managed files. It downloads changed, missing or
modified code only. Unchanged files require no download. A same-version run can
repair code damage. Locally edited root startup is preserved. Removed manifest
entries are left on disk rather than deleted automatically.

Before downloading replacement files, a self-contained recovery program is
written and verified at `/.autobuilder-install/transaction/recover.lua`. It remains
available throughout replacement of the main installer and every application file.
All replacement files are downloaded into `/.autobuilder-install/transaction/`,
checked for length, SHA-256 and Lua syntax, and only then prepared for commit. The
transaction keeps verified backups and a journal. Startup guards are promoted
first and the installation receipt last. A failed commit rolls back; a reboot
mid-commit stops startup until recovery. Leave enough space for the installed
files plus staged replacements and backups. This does not make Minecraft world
saves immune to filesystem or hardware failure.

To recover without HTTP:

```text
/installer.lua --recover
reboot
```

`/update.lua --recover` is equivalent. Recovery also runs automatically before a
new installer/update attempts network access. A power loss exactly while replacing
the installer itself may leave `/installer.lua` absent. The independent recovery
program remains available, without HTTP or any installed modules:

```text
/.autobuilder-install/transaction/recover.lua
```

Startup displays this path, and an intact `/update.lua` falls back to it if the
installer is missing. In an older transaction without the independent recovery
program, its backup installer can also recover:

```text
/.autobuilder-install/transaction/backup/installer.lua --recover
```

For a first install with no old installer, a complete staged installer can recover:

```text
/.autobuilder-install/transaction/stage/installer.lua --recover
```

If no recovery copy exists, rerun the online `wget run ... --recover` bootstrap, or copy a
known-good standalone installer from the desktop. Do not delete the transaction
directory to bypass a recovery error: it may hold the only complete backups.
Corrupt journals, corrupt backups and unknown staging directories stop with an
error for inspection rather than guessing. Recovery restores the previous release;
rerun update afterward to install the desired release.

## Offline computer folders

Generate a separate directory for each role/controller pairing:

```sh
python3 tools/release.py --offline dist/controller --role controller
python3 tools/release.py --offline dist/worker-12 --role worker --controller 7
python3 tools/release.py --offline dist/miner-13 --role miner --controller 7
```

Replace `7` with your controller ID. Folder names are your choice; they do not set
the device's numeric ID. Use `--role builder`, `logger` or `courier` for those
profiles. Output directories must not exist; the generator refuses to overwrite
an existing computer or output directory. No HTTP is needed to run these bundles.

1. Turn on the target computer once and run `id`.
2. Stop Minecraft/the server before changing world files externally.
3. For a fresh installation, copy the generated directory's **contents**, including
   `autobuilder/.installation.json`, to:

   ```text
   saves/<world>/computercraft/computer/<computerID>/
   ```

   On a dedicated server, use `<configured-world-folder>/computercraft/computer/<ID>/`.
   For example, `/startup.lua` in game must correspond directly to
   `<computerID>/startup.lua` on disk. Do not nest the generated folder inside it.
   On macOS/Linux, `cp -R dist/controller/. /path/to/computer/ID/` includes hidden
   files. Use an empty target directory and retain any preexisting files separately.
4. Edit `autobuilder/settings.lua` as needed, then start the world/server and reboot
   the computer. The standard startup selects its role from that configuration.

Never overwrite an existing installation with a fresh offline folder without
preserving its settings and state. For offline replacement, stop the server and
back up the entire old computer directory; generate a fresh folder, copy the old
`settings.lua`, `data/`, `logs/`, any custom root startup and unrelated user files
into it, then replace the old folder with the prepared one. Keep the backup until
verified. Carry local defaults into `settings.lua` instead of replacing new
`config.lua`. Never combine a pending transaction with this procedure; recover it
first. These desktop folder replacements are not the live updater transaction.

After an offline installation, online `update` works once a real base URL was
baked into the release or supplied with `/update.lua --base URL`. A placeholder
offline build remains fully usable offline.

## Developer verification

```sh
.venv/bin/python tests/run.py
.venv/bin/python -m unittest discover -s tests -p test_release.py
python3 tools/release.py --check
```

The Lua suite simulates HTTP, filesystem failures and recovery. Desktop tests
check manifest hashes, all offline roles, reproducibility and execution of the
standalone bundle using genuine JSON in Lua 5.2. No Minecraft installation or real
GitHub-hosted download was exercised in this environment; in-game installation,
disk-full behavior and reboot recovery remain acceptance checks on your server.
