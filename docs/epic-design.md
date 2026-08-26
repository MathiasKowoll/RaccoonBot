<!--
  Research note, not a specification. Everything load-bearing here was checked
  against a primary source or against this machine; where it was not, it says
  "unverified". Written before any Epic code exists, so the decisions can be
  argued with while they are still cheap to change.
-->

# Epic Games Store in RaccoonBot — Design Note

Scope: how Epic should be added, what changes in the library model, what abstraction to build. Research only; no repository files were modified.

---

## 1. The decision that matters most

### The save question, answered first

**The belief "game saves do not persist with legendary" is false.** Local saves are never at risk — legendary is not in the write path at all. The game writes into the bottle's filesystem like any other Wine application. What is absent is *Epic cloud* sync, and only because legendary was never designed to do it on launch.

This is verified in source, not inferred:

- `legendary/cli.py`, `launch_game()` spans L594–745 and ends at L744 with a bare `subprocess.Popen(full_params, cwd=..., env=..., shell=os.name == 'nt')`. There is no `.wait()`, and no call to `sync_saves`, `upload_save` or `download_saves` anywhere in those 152 lines. The contrast is deliberate: the optional *pre-launch* command three lines above does get `p.wait()` (L735).
- `sync_saves` lives at `cli.py:469` and is reachable only from the `sync-saves` / `download-saves` subcommands (dispatch at L3185–3187). `launch` has no save-related flag at all.
- Behaviour is byte-identical across 0.20.34 (2023-12-08), 0.21.0 (2026-08-04, current release) and master (pushed 2026-08-24). Nothing was broken and nothing was fixed.

Upstream corroboration, with status:

- **legendary-gl/legendary#90**, "Add update and sync-saves shorthands to launch command" — **OPEN since 2020-08-31**, last activity 2022-02-15. Six years. This is precisely the request to auto-sync on launch, never implemented and never triaged.
- **legendary-gl/legendary#502**, "Playtime and save are not uploaded to cloud or sync with Epic game launcher after closing a game" — **OPEN since 2022-11-29**, one comment. This is the owner's belief stated verbatim as a bug title. It is working as designed. Note: the sole comment ("this won't be implemented") is from `nutterthanos`, `author_association: NONE` — an ordinary user, not a maintainer. No maintainer ever responded. Do not describe this as "declined by upstream"; it is untriaged.

Canonical repository is `github.com/legendary-gl/legendary`; `derrod/legendary` 301-redirects to it. Use the former in any doc.

**There is one real, currently shipping save-loss bug**, and it deserves naming precisely because it sounds like the folklore: **issue #635, OPEN since 2024-01-09**. `core.py:1156` parses Epic's `CloudIncludeList` with `_include.split(',')` and never strips whitespace. For Fallout 3's `"falloutprefs.ini, *.fos"` the patterns become `['falloutprefs.ini', ' *.fos']`; the leading space makes both the `endswith` and `fnmatch` tests fail. Reproduced against master's filter function: `Save1.fos` → included `False`; with `.strip()` → `True`. Saves silently do not upload, reported only as an INFO line ("No files to upload"). Still present on master and in 0.21.0.

So the honest statement is: *legendary's launch path never syncs, by design, and that is not a bug; there is a separate, narrow, real filter bug (#635) that must be guarded against.*

### The route

**Ship Epic Games Launcher inside its own bottle (Route A) for v1. Do not put legendary in the v1 launch path.**

The reason is not that legendary is unreliable — it isn't, and the folklore should be retired. The reason is **who owns the cloud-sync loop**. EGL owns cloud saves, achievements, the EOS overlay and Epic's own telemetry, exactly as the Steam client does today. Under Route A, RaccoonBot writes zero save code and inherits the Steam-shaped design it already has. Under Route B, RaccoonBot must own the entire sync loop, per-title, forever, including the #635 workaround and conflict resolution that legendary's own source comment calls "mostly a guess" (`core.py:1115–1143`, 60-second `SAME_AGE` window at folder granularity).

Anti-cheat also favours Route A: EAC/BattlEye are far likelier to work when the game runs under the real client.

**Route A's costs, named honestly — they are real and version-pinned:**

- CodeWeavers rates the Epic Games Store "Runs Great" on Mac, last tested CrossOver 26.3.0 (`codeweavers.com/compatibility/crossover/epic-games-store`, page modified 2026-07-29). **Do not cite that badge as the justification.** It is 65% CodeWeavers' own rank by their published weighting, it is filed under "Game Tools" and rates the launcher UI, and on the same engine Steam — which RaccoonBot already ships successfully — is rated *lower* (Runs Well, 4/5). The scale is coarse.
- The justification to record instead is the **engine floor**: the CrossOver 26.3.0 release announcement (2026-07-21) lists exactly three fixes, all store clients broken by their own self-update, including *"Fix for Epic Games Launcher downloads not working on Mac after update."* Below 26.3.0, EGL downloads are known broken on Mac. Given that a bottle is pinned to its CrossOver version, a user below the floor never receives the fix.
- **Epic Online Services fails to install on macOS** with `EOS-ERR-1603`, reported 2025-10-09 and still unresolved as of 2026-01-22 on CodeWeavers' own forum (msg=331112). This gates multiplayer/anti-cheat titles independently of the storefront working. Surface it in the UI rather than letting titles look broken.
- **EGL self-update repeatedly bricks bottles.** Multiple unresolved reports; the only reliable recovery in every thread is recreating the bottle, and at least one user had to reinstall the games with it (msg=325987, 2025-04-07). Mitigate by defaulting `-SkipBuildPatchPrereq` into the Epic boot arguments, mirroring the existing hardcoded `steamBootOptions` at `/Users/mathias/Development/RaccoonBot/RaccoonBot/Util/Launcher.swift:224`.
- **~1.4 GB RSS** before a game starts (EpicGamesLauncher.exe ~770 MB + EpicWebHelper.exe ~600 MB, reported on CodeWeavers msg=344907). There is no supported bypass under Route A.

### The launch URL — the owner's likely first guess is wrong

The Epic analogue of `steam://rungameid/<id>` is **not** `com.epicgames.launcher://apps/<AppName>`.

Epic's own documentation (`dev.epicgames.com/docs/epic-games-store/protocol-activation`) gives the canonical form as:

```
com.epicgames.launcher://apps/[SandboxID]%3A[CatalogID]%3A[ArtifactId]?action=launch&silent=true
```

and explicitly describes the bare-ArtifactId form as "a deprecated format". In practice it stopped working: **r2modmanPlus#1973**, "Launching Through Epic Games Store Uses Deprecated/Removed URI Path" — opened 2025-10-21, **CLOSED 2025-11-13**, fixed in r2modman 3.2.10. The issue body reports the bare form was removed from the launcher, with an EGS log screenshot emitting `unable to parse URI`.

A documented fallback exists and puts a URL-encoded **install directory** in the same slot — this is what dlss-swapper actually does (`GameManager.cs:507–508`, passing `NormalizePath(manifest.InstallLocation)`). Use it as a second attempt when any component of the triple is missing. **Never emit the bare artifact id.**

Also: `silent=true` is a per-request URI parameter meaning "put the launcher in the background", not an analogue of Steam's `-silent -no-browser` process flags. Do not conflate the two layers.

Fire the URI through Wine's `start`, not macOS `open` — macOS `open` would hit the host handler and bypass the bottle entirely. The `com.epicgames.launcher` protocol handler is confirmed registered in the existing bottle's `system.reg` at `Software\Classes\com.epicgames.launcher`.

**Unverified and worth testing before anything else is built:** that a fresh EGL install signs in and launches a game inside a CrossOver 26.3.0 bottle *on this machine*, via `wine --bottle <name> start "com.epicgames.launcher://apps/<triple>?action=launch&silent=true"`. Everything downstream depends on it and nothing in the research substitutes for running it once.

### Where legendary belongs

Later, optional, never default, not a v1 dependency. Its genuine advantages are underweighted in the current discussion: it has **first-class CrossOver support already** — a `legendary crossover` setup subcommand (`cli.py:2423`), `--crossover-app` / `--crossover-bottle` on launch (`cli.py:2942–2947`, darwin-gated), per-game `crossover_app`/`crossover_bottle` config keys, `CX_BOTTLE` handling, and save-path resolution that reads the bottle's own `user.reg` shell folders (`core.py:1030–1105`). It is built for exactly RaccoonBot's deployment shape. That fact, not the save folklore, is the real argument on its side.

If it ever ships, four non-obvious constraints:

1. Build on **`legendary launch <app> --json`** (`cli.py:2921`), which returns resolved launch parameters and exits *without* launching. Spawn and supervise the process yourself. Plain `legendary launch` detaches, so "run it then sync on exit" is impossible as written. This also keeps RaccoonBot's existing per-game options, env vars and graphics machinery applying uniformly.
2. Copy Heroic's direction-locked shape: pre-launch `sync-saves --skip-upload`, post-exit `sync-saves --skip-download`, always with an explicit `--save-path` and `-y` (`Heroic backend/launcher.ts:159, 311`; `storeManagers/legendary/games.ts:846–866`). Never a bare bidirectional `sync-saves` around a session.
3. One-time per title, resolve the save path non-interactively with `-y ... --accept-path`. Without `--accept-path`, `-y` makes legendary *silently skip* a title whose path is unset (`cli.py:513–515`); without `-y` it calls `input()` and hangs a GUI forever.
4. Guard #635: if a post-exit upload logs "No files to upload", retry once with `--disable-filters`. Roughly five lines, and it closes the only live save-loss path.

**Playtime is unsolvable via legendary and should not be promised.** `grep -rn playtime legendary/` returns zero hits — the feature does not exist. Heroic tracks Epic playtime locally and never pushes it to Epic (`postPlaytimeSession` is GOG-only). Nobody in the open-source world reports Epic playtime.

---

## 2. What can be read from disk, and what cannot

RaccoonBot's Steam library model — read the client's own files, no network, no API key — **survives only partially for Epic.** This is the single biggest architectural consequence and it should be decided deliberately rather than discovered.

### Survives

**Installed titles.** `<bottle>/drive_c/ProgramData/Epic/EpicGamesLauncher/Data/Manifests/*.item` — one plain UTF-8 JSON file per installed title. Confirmed on this machine: the existing "Epic Games Store" bottle holds 8 of them. This is the `appmanifest_*.acf` analogue and it is strictly richer *within that scope*: `DisplayName`, `InstallLocation`, `InstallSize`, `AppName`, `CatalogItemId`, `CatalogNamespace`, `LaunchExecutable`, `AppCategories`, `MainGameAppName`.

Two implementation details that will otherwise cost a day each:

- **Take the id from inside the JSON, never from the filename.** The file is named `<installation_guid>.item` (`legendary/lfs/egl.py`, `set_manifest`). Epic's id is a field, not a filename pattern. This is different from `extractAppIDRegex` at `/Users/mathias/Development/RaccoonBot/RaccoonBot/Util/Misc.swift:161`, which parses the app id out of `appmanifest_(\d+)\.acf`. Mirror legendary's `read_manifests()` instead: glob the extension, key on `AppName`.
- **Decode permissively.** Diffing a real manifest against legendary's own template found 7 keys present in real data that the template does not know, and 1 in the template absent from real data. Swift's `JSONDecoder` ignores unknown keys fine but **throws on a missing key bound to a non-optional property**. Make everything optional except `AppName`.

**Where the Manifests folder is, without hardcoding.** The bottle's `system.reg` carries `[Software\\Wow6432Node\\Epic Games\\EpicGamesLauncher]` with `"AppDataPath"="C:\\ProgramData\\Epic\\EpicGamesLauncher\\Data\\"`. Verified on this machine at line 105868 of the existing Epic bottle's `system.reg`. Note three things: the casing is **`Wow6432Node`**, not `WOW6432Node` (SKIF's uppercase spelling appears only in a prose comment; its code reaches the key via the `KEY_WOW64_32KEY` redirection flag, which does not exist for a `.reg` parser — and `WineRegistryFile.section(forPath:)` at `/Users/mathias/Development/RaccoonBot/RaccoonBot/Util/WineRegistry.swift:249` is an exact case-sensitive compare that will silently return `nil`); the value has a **trailing backslash**; and `unquote()` at `WineRegistry.swift:238` strips outer quotes only, so it will hand back literal `\\` sequences. No caller has ever read a REG_SZ path through that parser. Budget ~20 lines to add unescaping.

**The launch triple.** `<bottle>/drive_c/ProgramData/Epic/UnrealEngineLauncher/LauncherInstalled.dat` is JSON with an `InstallationList[]` carrying `NamespaceId`, `ItemId`, `ArtifactId`, `AppName`, `InstallLocation`. This is the only file that names `ArtifactId` explicitly; prefer it, fall back to the `.item` file's `AppName`. This is what shipped r2modman reads (`src/r2mm/launching/runners/multiplatform/EgsGameRunner.ts:68–89`).

**The launcher exe path.** Also in the registry: `Software\Wow6432Node\EpicGames\Epic Games Updater` → `EpicGamesLauncherExecutable`, and `Software\Classes\com.epicgames.launcher\shell\open\command`. So the `storeClientExePath` parameter can be filled per store from that store's own registry footprint rather than hardcoded — which is exactly the seam that already exists, generalised without inventing anything.

### Does not survive

**Cover art. There is no local cache.** `VaultThumbnailUrl` exists in the manifest but is **empty in real data**. There is no Epic analogue of `appcache/librarycache`. Epic covers require the network or placeholders. This is the piece `/Users/mathias/Development/RaccoonBot/RaccoonBot/Util/LocalLibrary.swift` solves for Steam and cannot solve for Epic — its `artCaches()` per-bottle scan is precisely the code with no Epic counterpart. **The "library works with no network" property RaccoonBot has today will not hold for Epic.** That is a product decision, not an implementation detail.

**Owned-but-not-installed titles.** No local source without Epic authentication. Confirmed in legendary: `core.get_assets` returns `[]` when `not self.egs.user`. That is why legendary requires login. If RaccoonBot stays no-network/no-auth, the Epic library shows **installed titles only** — no `appinfo.vdf` equivalent.

*Partially verified lead:* `<AppDataPath>/Catalog/catcache.bin` is base64-wrapped JSON (documented by rai-pal, `epic_provider.rs:202`). On this machine it decodes to 256 catalog entries, 59 with `categories.path == "games"`. **Unverified** whether that reliably covers owned-but-not-installed titles or is merely a browse cache. Worth one hour of checking before writing off the owned list entirely.

**Playtime and last-played.** Epic stores nothing locally. There is no `localconfig.vdf` analogue. RaccoonBot must record this itself at launch/exit. Do not design toward parity with the Steam view here — for Steam the numbers are read out of Steam's own files, and for Epic no equivalent exists at any price.

### Two disk traps that will break a naive implementation

**Every path in a `.item` is a Windows path, and on this machine none of them are on C:.** All 8 manifests in the existing bottle use `Z:\Volumes\Crucial X8\EpicGogGames\...`, with `Z:` symlinked to `/`. That is 24 of 24 drive-letter occurrences on `Z:`, zero on `C:`. A `drive_c` + `dropFirst(2)` implementation resolves the *Manifests* folder correctly and then fails to find a single game. The correct mechanism is what legendary does in `egl_import()` (`core.py:1988–2003`): lowercase the drive letter, `realpath` `<prefix>/dosdevices/<letter>`, then join the remainder.

Three sub-traps:

- **Mixed separators inside one string.** EGL writes `Z:\Volumes\Crucial X8\EpicGogGames/Venus`. Normalise both `\` and `/`. Do not `components(separatedBy: "\\")`.
- **Do not copy legendary's error check.** `if 'dosdevices' in mapped_path` catches only a *missing* symlink; a **dangling** one (unmounted volume) resolves cleanly out of `dosdevices` and passes, yielding a confident path to nothing. 14 of ~16 drive letters in the real bottle are dangling stale DMG mounts. Test the resolved path for existence instead.
- **`LaunchExecutable` must not go through the resolver.** It is a bare relative filename (`Borderlands4.exe`, `ys9.exe`) or empty — 0 of 24 drive-letter occurrences. Join it onto the already-resolved `InstallLocation`. `ManifestLocation` and `StagingLocation` *do* need resolving. Getting this backwards breaks every launch.

**The phantom-library bug, which will ship on day one if discovery works the way Steam discovery does.** The Epic profile is cloned across four bottles on this machine — Steam, Epic Games Store, SteamProcyon, SteamPreview. `EpicGamesLauncher.log`, `Cookies` and `Network Persistent State` are identical MD5s in all four, which is impossible if EGL had genuinely run in each; birth times show the original in the "Epic Games Store" bottle (2025-08-27 16:11) fanned out to the other three at a single instant (2026-06-28 23:26). If Epic discovery scans *any bottle containing EGL*, it finds the launcher in four bottles and the same 8 manifests in four bottles and surfaces ~32 games, three-quarters of them unlaunchable residue. **Epic library reads must be keyed to the one designated Epic bottle from config.** Steam has never exposed this because there is only one real Steam install.

### Filters, or the library fills with junk

Three predicates, all backed by primary source:

- `AppCategories` contains `"games"` — excludes Unreal Engine, launcher components, tools. Both SKIF and rai-pal filter on this. On this machine only 4 of 8 manifests qualify.
- `bIsIncompleteInstall == false` — excludes partial downloads.
- DLC: **do not copy legendary's predicate.** legendary uses `main_game_appname == app_name` (`core.egl_get_importable`), but in the real `.item` data on this machine `MainGameAppName` is the **empty string** for base games, so that test would drop them. Use: DLC iff `MainGameAppName` is non-empty **and** `!= AppName`. Expect several manifests pointing at one install folder — 5 of the 8 here share a single game directory.

Also: 4 of 8 manifests have an **empty `LaunchExecutable`**. Treat it as optional. That empty field is itself an argument for handing the id to the client rather than exec'ing the binary.

---

## 3. The abstraction

### The seam that is right, at the wrong line

`launchWindowsGame(id:cxAppPath:selectedBottle:steamExePath:options:appExeURL:)` **is the right seam.** Rename `steamExePath` → `storeClientExePath`. But the generalisation must happen at the **launch**, not the install.

- `/Users/mathias/Development/RaccoonBot/RaccoonBot/Util/Launcher.swift:143` — `runSteamAction`, which passes the `steam://` URL as a positional argument. Its **only** caller is `installGame` (L298–301) passing `.install`. The `.run` and `.validate` cases (L123–124) have **no callers anywhere in the tree** — dead enum cases. Generalising this line generalises install, which is genuinely near-free, but it is not the launch.
- `/Users/mathias/Development/RaccoonBot/RaccoonBot/Util/Launcher.swift:243` — the actual launch:

  ```swift
  let gameLaunchCommand = appExeURL != nil ? "\"\(appExeURL!.path(percentEncoded: false))\"" : "\"\(steamExePath)\" \(steamBootOptions) -applaunch \(String(id))"
  ```

  That is a **flag**, not a protocol URL. Epic has no `-applaunch`; for Epic the protocol URI *is* the launch mechanism.

**Turn that ternary into a three-case switch on the game's store, computed inside the function.** Everything below line 243 — `copyMoltenVK` (L180–182), the winebus registry DWORDs (L200–217), `getInlineEnvs` + `CX_ROOT` + `WINEPREFIX` + `WINEDEBUG` + `WINEMSYNC` (L239), `installd3dMetal` (L249–260), the x87 bundle swap (L262–268) — then applies to Epic unchanged. That is the homogenisation design point 2 asks for, and it really is small.

If instead only line 143 is generalised, the two stores end up launching through structurally *different* functions and Epic titles get **none** of the per-game options machinery. "Costs almost no new launch code" is true only for a version of Epic with no options.

Quoting matters: `safeShell` runs `/bin/zsh -c` on a composed string. The Epic argument contains `?`, `&` and a leading `-`, so it must sit inside escaped double quotes exactly as line 143 already quotes `action.url`, with the flags as separate tokens outside. Getting this wrong fails as zsh globbing or backgrounding, not as a clean error.

### The per-game bottle boolean is the wrong seam to build on

`useArmBottle` (`/Users/mathias/Development/RaccoonBot/RaccoonBot/Util/GameLauncher.swift:126–128`) is a **per-title override on top of a default**. Store→bottle is not an override; it is a *mapping from the game's identity*, resolved before per-game options are read. Modelling the store as another boolean that swaps bottles will collapse the moment a third store lands, and it puts store routing inside the options layer where it does not belong.

Instead: make bottle resolution a function of `(store, options)` — the store selects the bottle, then `useArmBottle` may still override *within* that store's family, exactly as it does today. Leave `useArmBottle` alone; do not generalise it.

### The identifier is the actual project

This is the piece that will cost real time, and it is invisible from the launch string.

`Game.steamAppID` is an `Int` (`Types.swift:199–345`), and it is load-bearing in `namespacedKey("GameOptions", id)`, in `getGameTracker(steamID: Int?)`, and in both watchers. **Steam is one integer. Epic is a three-part tuple. Battle.net is a different shape again** — dlss-swapper runs `Battle.net.exe --exec="launch <LauncherId>"` (`GameManager.cs:526`), not a URL at all.

**This is where the owner's design point 2 is wrong.** Homogenising options, parameters and the library model is correct and should proceed. Homogenising the launch *identifier* into a scalar `storeGameId` is not — it bakes in a shape that two of three stores do not have. Make the identifier an enum with per-store associated values (`.steam(Int)`, `.epic(namespace:catalogItemId:artifactId:)`, `.battleNet(String)`), keyed for persistence by a store-tagged string. Keep the homogenisation at the options and metadata level, where it genuinely holds.

Do **not** add `epicAppName: String` mirroring `steamAppId`. A scalar rename bakes in the deprecated bare-artifact-id form and is expensive to undo once it is in the persisted per-title options store.

### Process tracking is the hidden cost

`getGameTracker` (`Misc.swift:457`) takes `steamID: Int?` and drives two watchers that **parse Steam's own log files keyed by integer AppID**: `SteamLaunchWatcher` tails `gameprocess_log.txt` for `"AppID <id> adding PID"` and regex-extracts the `.exe` name; `SteamCloudSyncWatcher` tails `cloud_log.txt` for `"[AppID <id>]"` + `"Successfully synced"` before quitting the client. Epic writes neither file.

The launch watcher's output populates `appNames`, which is what the `NSWorkspace.didTerminateApplicationNotification` observer (`/Users/mathias/Development/RaccoonBot/RaccoonBot/Util/NotificationObservers.swift:48` — not `Misc.swift`) matches on. With no substitute there is no playing state, no loader dismissal, no termination hook, and no post-game client quit.

**The `.item` manifest replaces `SteamLaunchWatcher` cleanly**: `LaunchExecutable` gives the exe basename directly, feeding `appNames` without any log parsing. That is a better mechanism than the Steam one and it comes free with the library scan.

`SteamCloudSyncWatcher` has **no** Epic replacement. There is no log to wait on. Make the call conditional on store and give Epic a bounded grace period instead — but do not let it silently no-op, because a premature quit here loses saves, which is the exact risk the owner is worried about in the other direction. **Unverified:** what EGL actually writes on quit and how long a safe grace period is. Measure it; do not guess. The existing 60s timeout shape (`Misc.swift:377`) is the right pattern but the deadline is not transferable.

`quitSteam` (`Launcher.swift:79`) hardcodes `"C:\Program Files (x86)\Steam\Steam.exe" -shutdown`. It must become `quitStoreClient`. Epic has no documented `-shutdown`; Epic falls back to `closeWineActivities()` / `wineserver -k`.

### DLL overrides: use the env var, not the registry

Verified in Wine's own source — `dlls/ntdll/unix/loadorder.c` resolves load order as "1. The `WINEDLLOVERRIDES` environment variable 2. The per-application DllOverrides key 3. The standard DllOverrides key", with `get_load_order_value()` querying `app_key` before falling back to `std_key`.

Per-exe `AppDefaults` overrides **work and are in live use** — the Steam bottle's `user.reg` has entries at line 1479 (`NieR Replicant ver.1.22474487139.exe` → `"dinput8"="native,builtin"`) and 1483 (`NINJAGAIDEN4-Steam.exe` → `"nvapi64"=""`), with key timestamps decoding to 2026-08-25 and 2026-08-24. But they match on **executable basename only** (confirmed in Wine's `dlls/ntdll/version.c`: `if ((p = wcsrchr(appname, '\\'))) appname = p + 1;`), so they cannot distinguish two games shipping the same exe name — common with Unreal titles — or the same game owned on two stores.

**`WINEDLLOVERRIDES` in the environment string RaccoonBot already builds at `Launcher.swift:239` is the correct per-game mechanism.** It outranks both registry layers, scopes to the process RaccoonBot spawns, needs no registry write, leaves no residue, and generalises to Epic and Battle.net **with zero per-store branching**. The project had this and removed it — see the trailing comment at `/Users/mathias/Development/RaccoonBot/RaccoonBot/Components/GameOptionsView.swift:87`. **Unverified: why it was removed.** Find out before re-adding; there may be a reason not visible in the diff.

### The graphics conflict nobody has resolved

`cxGraphicsBackend` is a **per-game** option (`Launcher.swift:252`) and `installd3dMetal` writes into the CrossOver **engine**, not the bottle (`installd3dMetal(at: cxAppURL, ...)`, L252–259). Meanwhile CrossOver's `cxbottle.conf` holds `CX_GRAPHICS_BACKEND` **per bottle** — the existing Epic bottle carries `CX_GRAPHICS_BACKEND = "d3dmetal"`, `WINEMSYNC = "1"`, `D3DM_ENABLE_METALFX = "1"`, `DXMT_ENABLE_NVEXT = "1"`.

Under Route A, EGL and the game share one launch, so one graphics choice has to serve both. Community guidance for rendering the EGL CEF UI (Graphics Auto, DXVK off) conflicts with what games want (D3DMetal). **One store, one bottle does not resolve this** — the conflict is launcher-vs-game *inside* one bottle. Decide deliberately: either a store-level graphics setting applied while the client boots, or accept the game's setting. **Unverified: whether EGL's UI renders correctly under D3DMetal on 26.3.0.** One test settles it.

Related: do not copy Lutris's `-opengl` flag blindly (`lutris/services/egs.py`, `get_launch_arguments()`). It is a Linux workaround for the launcher's embedded CEF renderer under Wine/OpenGL. On CrossOver with D3DMetal it may be wrong or unnecessary. Treat it as a variable to test — the concern is familiar, since RaccoonBot already passes `-no-cef-sandbox` to Steam for the same class of problem.

---

## 4. One store, one bottle

**Endorse it. Change the justification.**

Two arguments commonly used for it are refuted and should be dropped:

- **"DLL override collisions."** Diffing the prefix-wide `[Software\Wine\DllOverrides]` blocks across all three existing bottles: Steam 59 keys, Epic Games Store 58, Battle.net 109 — and **zero keys with differing values** in any pair. Epic's set is a strict subset of Steam's; Battle.net is purely additive. The union is well-defined with no merge decisions. Per-app overrides work, and Windows version is per-app scopable too (`version.c` reads `HKCU\Software\Wine\AppDefaults\<exe>` before falling back). This class of conflict does not justify a split. *(Fix a citation while you are here: the prefix-wide `DllOverrides` block is at `user.reg` line **1529**, not ~1461; line 1461 is `[Software\Wine\AppDefaults\cxcplinfo.exe\Explorer]`.)*
- **"Epic is already co-resident in the Steam bottle and it works."** It is co-resident, but it has never been *run* there. As established in §2, the profile is a byte-identical clone fanned out from the Epic bottle. The two-client experiment has not been performed on this disk; nothing passed. Conversely, the owner's actual layout — a dedicated "Epic Games Store" bottle with no `Steam.exe`, and a separate "Battle.net Desktop App" bottle — shows he **already** follows the rule.

**The justification that holds, in order of weight:**

1. **CrossOver-specific, and decisive.** `cxbottle.conf` pins the bottle to a CrossOver engine version (`[Bottle] "Version" = "26.3.0.39832"` in the existing Epic bottle) and holds the graphics backend and env vars for everything inside it. Steam and Epic **cannot** have different engines or different graphics backends in one bottle. This matters concretely: Epic needs an **engine floor of 26.3.0** that Steam does not need. That asymmetry alone forces separate bottles.
2. **Blast radius.** EGL self-update bricking is the most likely support burden by a wide margin, and every reported recovery is "recreate the bottle". The bottle is the blast radius. Keeping Steam out of it is worth more than the disk it costs.
3. **Wine-generic.** One prefix is one C: drive and one registry, so two clients share `Program Files`, `ProgramData`, and `users/<user>/AppData` — which is where game saves live. Note this cuts the *opposite* way from how it is usually framed: bottle separation gives save isolation between stores for free, regardless of how Epic is launched.

**The cost, named:**

- **~1.8–1.9 GB of Windows tree per bottle** (measured: Steam `drive_c/windows` 1.9 GB, Epic 1.8 GB), plus duplicated redistributables, plus a separate engine-upgrade path per bottle.
- **Game payload costs nothing.** All 8 Epic manifests point at `Z:\Volumes\Crucial X8\...` and `Z:` maps to `/`. The games sit on an external drive visible from every bottle. Only `drive_c/ProgramData` manifests and the ~476 MB `AppData` launcher profile duplicate. This removes the main cost objection.

**Two operational rules that follow:**

- **Never clone a bottle that contains a signed-in store client.** Provision fresh and sign in. Cloning is what produced identical Epic cookies, session IDs and machine-secret across four bottles here — presenting Epic with one machine identity across several supposedly distinct installs. Not yet exercised, but it is a real way to trip device checks.
- **Make bottle recreation a first-class, non-destructive RaccoonBot repair action**, or keep Epic game installs on a path that survives it. Under Route A the games would otherwise sit inside the thing you have to throw away.

---

## 5. What to build first

Each step is independently useful and independently shippable. Nothing here is a big-bang rewrite, and the first three land even if Epic never does.

**Step 1 — Windows-path resolver, extracted and hardened. (Steam-only benefit, ships alone.)**

Add `resolveWindowsPath(_ winPath: String, inBottle: URL) -> Resolution` on top of the existing `getBottleDrives(bottleURL:)` at `/Users/mathias/Development/RaccoonBot/RaccoonBot/Util/Crossover.swift:471`, and refactor the ad-hoc transform currently inline in `getSteamLibraryFolders` (`Misc.swift:~297`) onto it. Requirements: normalise both separators; key on exactly letter+`:` (CrossOver also creates `d::` → `/dev/rdisk7s2` entries alongside `d:`); cache the drive map once per bottle per scan; and return **three states** — resolved-and-present / drive-maps-but-target-absent / no-such-drive-letter. The existing code uses `destinationOfSymbolicLink` (raw target, not realpath) and performs no existence check, so all 14 dangling drives currently come back as apparently-valid URLs.

Then surface the middle state in the UI: **"installed, volume offline"**. Steam libraries on external drives get a correct greyed-out state today instead of silently vanishing or flipping to not-installed — which would invite a redownload. This is a real Steam bug fix, and it is a hard prerequisite for Epic, where 100% of games on this machine live on `Z:`.

**Step 2 — Per-game `WINEDLLOVERRIDES`. (Steam-only benefit, ships alone.)**

Add it to the environment string at `Launcher.swift:239`. First, find out why it was removed (`GameOptionsView.swift:87`). Immediate win for Steam titles needing native DLLs; scopes per-process, so it sidesteps the basename-collision limitation of `AppDefaults`; and it is the one per-game mechanism that generalises to every future store with zero branching.

**Step 3 — Land the launch seam with one case. (No behaviour change.)**

Rename `steamExePath` → `storeClientExePath`; turn the `Launcher.swift:243` ternary into a switch with `.steam` and `.direct` cases only. Separately generalise `runStoreAction` at L143 for install — but decide first whether to wire or delete the dead `.run`/`.validate` cases, and note the action enum must become store-*aware* rather than shared: Epic has `?action=install` but no analogue of `steam://validate`.

**Step 4 — Store-tagged game identity.**

Replace `Int steamAppID` with `store: Store` + a per-store identifier enum, threaded through `Types.swift`, `namespacedKey("GameOptions", id)` and `getGameTracker`. Mechanical, wide, and the enabling refactor for everything after it. Do it before any Epic code so it is one migration, not two.

**Step 5 — One empirical test, before writing Epic code.**

Install EGL into a fresh bottle on CrossOver 26.3.0, sign in, and launch a game via `wine --bottle <name> start "com.epicgames.launcher://apps/<ns>%3A<itemId>%3A<artifactId>?action=launch&silent=true"`. Confirm: sign-in works; the triple URI parses; the game starts; EGL's UI renders under whatever graphics backend is set. **This decides everything downstream and none of the research substitutes for it.** If it fails, the whole route changes and nothing built in steps 1–4 is wasted.

**Step 6 — Epic library, read-only. No launching.**

Registry `AppDataPath` (with the `Wow6432Node` casing, trailing-backslash trim, and the `unquote()` unescaping fix at `WineRegistry.swift:238`) → `Manifests/*.item` → filters (`AppCategories` contains `"games"`, `bIsIncompleteInstall == false`, DLC iff `MainGameAppName` non-empty and `!= AppName`) → resolve `InstallLocation` through step 1's resolver → merge `LauncherInstalled.dat` for the triple. **Keyed strictly to the one configured Epic bottle.** Detect Epic by filesystem (`<AppDataPath>/Manifests` exists, or the launcher exe exists), not by registry presence — SKIF's own code comment says the registry value "does not exist (which happens surprisingly often)".

Ships as a visible, non-launchable Epic library. Useful on its own, and it forces the cover-art and owned-titles product decisions into the open before they can be papered over.

**Step 7 — Epic launch.**

Store switch case at `Launcher.swift:243`; engine floor gate for Epic bottles (gate it where version-gating already happens — `Launcher.swift:226` already does `EngineLayout.of(...) == .cx26`); `-SkipBuildPatchPrereq` in the default boot arguments; exit detection via the manifest's `LaunchExecutable` feeding the existing `NSWorkspace` termination observer; a bounded, measured grace period in place of `SteamCloudSyncWatcher`; `quitStoreClient` falling back to `wineserver -k` for Epic.

Add a launch-failure signal. `wine start` returns 0 regardless, and EGL **silently no-ops** on an unparseable URI — that is exactly why r2modman's breakage was reported as "Launch modded will do nothing". Do not treat exit code 0 as "launched"; poll for the game process. Without this, a whole class of bug is invisible to you and to users.

**Step 8 — Epic install/uninstall** via `?action=install`, reusing the generalised `runStoreAction`.

**Later, optional, explicitly not v1 — legendary "lightweight mode."** Per-game toggle, default off. Built on `legendary launch --json`, Heroic's direction-locked sync pair, `--accept-path` resolution, and the #635 guard. Pin and vendor an exact version: 0.21.0 shipped three weeks ago after ~2.7 years of dormancy and is the least battle-tested legendary in years (ChunksV5, manifest encryption, Python 3.10 minimum). Budget for issue **#778** (OPEN, filed 2026-08-12): `sync-saves` re-hashes every file in the save folder on every upload with no per-file cache, so post-exit sync is visibly slow on large save folders.

---

### Marked unverified

- EGL installs, signs in and launches inside a fresh CrossOver 26.3.0 bottle on this machine. **Not tested. Step 5 exists to close this.**
- The triple-form URI actually launches when fired via `wine --bottle <name> start` from outside the bottle. Not tested.
- Whether `catcache.bin` covers owned-but-not-installed titles or is only a browse cache.
- Whether EGL's CEF UI renders under `d3dmetal`, and whether `-opengl` is needed or harmful on CrossOver.
- What EGL writes on quit, and therefore how long the Epic post-game grace period should be.
- Why `WINEDLLOVERRIDES` was removed from the project previously.
- Whether Battle.net's `--exec="launch <id>"` shape holds under CrossOver — asserted from dlss-swapper source, not tested here.
