# Epic Games Store: bringing your own bottle

RaccoonBot opens the Epic Games Launcher in the bottle you choose. It does not
install Epic, does not repair a launcher that will not start, and does not
carry games over from one place to another. Making the bottle work is done in
CrossOver, once, by you. This page is what that takes, and how to keep the
result.

Everything below was checked on a Mac running RaccoonBot 0.2.1 with a
CrossOver 26.3 engine, on 2026-09-02.

## Install Epic from Epic's own installer, not from CrossOver's wizard

CrossOver's "Install a Windows application" wizard offers Epic Games Store and
installs it from a copy of the installer it keeps in its own cache. On the
machine this was measured on, that copy was **EpicInstaller-18.1.3.msi from
April 2025**, and the launcher it puts down is a 32-bit Unreal 4.27 build that
does not start on a 26.3 engine: it creates a Direct3D 11 device, every
shader it then tries to create is refused, and it shows **"Unsupported
Graphics Card"** and quits. It never gets far enough to update itself, so it
never gets better.

The current installer from Epic puts down a launcher that starts, updates
itself to Unreal 5.5, and runs. Get it from Epic directly:

- The download page: <https://store.epicgames.com/download>
- The installer itself, always the current one: <https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi>

Install it into a bottle made by the engine RaccoonBot uses — the copy called
`Crossover_MGVF.app` — so the bottle lands in RaccoonBot's own bottle folder
and is built by the same engine that will run it. Open that application,
create a bottle (Windows 10, 64-bit), and run the `.msi` in it. Let the
launcher update itself on first start; that takes a few minutes and is the
part that matters.

You can install Epic into the same bottle as Steam. That is how it is set up
on the machine this was measured on.

## Point RaccoonBot at it

In RaccoonBot, Options, the **Epic Games** tab: choose the bottle. If the
Epic tab has no bottle chosen, RaccoonBot uses the Steam bottle, which is
right when Epic lives there. An **Open Epic Games Launcher** button appears
in the Epic tab and beside the Steam button in the toolbar as soon as the
launcher is actually found in that bottle, and not before.

## One rule: the bottle can be older than the engine, never newer

A bottle records which CrossOver made it. When a different CrossOver opens
it, wine updates the bottle's own Windows files to match the engine that is
opening it — and with an *older* engine that is a downgrade, which is how a
bottle that works stops working. RaccoonBot refuses to open a bottle whose
recorded version is newer than the engine's, and says so in the log rather
than opening it anyway.

So: make the Epic bottle with the engine RaccoonBot uses, or with an older
CrossOver, and it will be fine. Do not make it with a newer CrossOver and
then hand it to RaccoonBot.

## Back up the bottle, and restore it

A bottle is a folder, and CrossOver can pack one into a single portable file.
Use the `cxbottle` tool from the engine RaccoonBot uses, so paths resolve
under RaccoonBot's bottle folder rather than CrossOver's:

```bash
~/Applications/Crossover_MGVF.app/Contents/SharedSupport/CrossOver/bin/cxbottle --bottle Steam --tar ~/Desktop/Steam.cxarchive
```

That writes a gzip-compressed archive of the whole bottle. It is as large as
the bottle; games installed *inside* the bottle come along, games installed
on another drive do not, and do not need to.

To bring it back on this or another Mac, with the same engine installed:

```bash
~/Applications/Crossover_MGVF.app/Contents/SharedSupport/CrossOver/bin/cxbottle --bottle Steam --restore ~/Desktop/Steam.cxarchive
```

The bottle appears under `~/Library/Application Support/RaccoonBot/CXPBottles/`
and shows up in RaccoonBot's bottle pickers. The rule above applies to a
restored bottle exactly as to a new one: it carries the version of the
CrossOver that made it.

## Games you already have on disk

The launcher decides what is installed from its own records inside the
bottle, not by looking at folders. A game folder that Epic itself installed
carries an `.egstore` directory with the game's manifest, and the launcher
can adopt such a folder: in the launcher, choose **Install** for the game,
point it at the existing folder, and it verifies the files instead of
downloading them again. Do that once per game.

Moving the launcher's records between two bottles by hand works only when
both bottles map the game's drive to the same letter, and is not something
RaccoonBot does for you.

## See also

- [Epic Games Store in RaccoonBot — Design Note](epic-design.md), for how
  Epic fits the library model and what was decided about saves, launch URLs
  and bottles.


## Play, and the launcher's quiet start

Play on an Epic title does not run the game's `.exe`. It runs the Epic
launcher in its bottle with the launcher's own URI for the title:

    com.epicgames.launcher://apps/<namespace>%3A<catalogItemId>%3A<AppName>?action=launch&silent=true

That is the form the launcher's desktop shortcuts use, and the launcher is
registered in the bottle as the handler for the scheme. `silent=true` keeps
the launcher's window out of the way; the launcher, signed in, starts the
game, so the game gets its account, the overlay and cloud saves. The three
ids come from the title's `.item` manifest.

Because RaccoonBot starts the launcher itself, the per-game options --
graphics backend, D3DMetal generation, environment variables, msync -- are
set on the launcher and inherited by the game. If a launcher is **already
running** in the bottle (opened from the Epic panel, say), the new one hands
the URI over and exits, and the game inherits the running launcher's
environment instead. For the options to apply, let Play start the launcher.

What the 5.5.4 launcher accepts on its command line, read from the binary
(2026-09-02): `-silent` (start in the tray, no window; it registers itself
at Windows start-up as `-silent -launchcontext=boot`), `-noselfupdate`,
`-nullrhi` (no rendering at all -- the launcher then cannot show anything,
which is not what a Play needs), `-forwarduri` and `-newinstancecommand`
(how a second launcher hands a URI to the first). There is no fully headless
mode that launches games without the launcher's session.


## When the game ends

The launcher uploads cloud saves after a game exits, as Steam does, and is
just as easily killed in the middle of it. So after an Epic title exits
RaccoonBot does, in this order: follow the launcher's own log
(`AppData\Local\EpicGamesLauncher\Saved\Logs\EpicGamesLauncher.log`)
until it has been quiet for a few seconds, bounded by a minute; ask the
launcher to leave with `taskkill /IM EpicGamesLauncher.exe` (no `/F`: that is
the close-button request, not a kill); wait for its processes to go as it
waits for Steam's; and only then end the prefix. Steam's own shutdown is not
sent: with no Steam running, `Steam.exe -shutdown` would start one.

Stop on a running Epic title asks the **game** to close, not the launcher --
most games save and quit on that request -- and the sequence above follows.

What the launcher writes when it syncs is not measured yet: no game had run
through the launcher here when this was written. The first real session's
lines are put in RaccoonBot's console (`epic launcher: ...`); once read, the
phrase that ends the sync belongs in `EpicSettle.isTerminal`.


## Where the launcher keeps "installed" (5.5 and later)

Copying a game's `.item` manifest into `Data\Manifests` used to be enough
for the launcher to list it as installed. It is not any more. The launcher
that updated itself to 5.5.x on 2026-09-02 hands the installation list to
the Epic Online Services helper (EOSH) and, at every start, reconciles the
manifests against what the helper reports:

    EOSH reconciliation: removing installation not reported by EOSH '...\<guid>.item'

Every manifest the helper does not know is deleted. The helper's own record
of installations is

    C:\ProgramData\Epic\EpicOnlineServices\InstallHelper\InstalledItems\

one `<InstallationGuid>.egi` per installation (JSON, `v4`), a
`Revision.json` (`timestamp` in .NET ticks, `number`), and a `ManifestCache`
of build manifests named by their SHA-1. A record's `revision` is the
timestamp as 16 hex digits followed by the number as 16 hex digits. The
helper enumerates the folder at every start, so records written while the
bottle is down are read at the next boot. `state` for a finished install is
`Installed`; the helper's own log line says as much.

So, to bring an installed game into a bottle: its `.item` into `Manifests`,
a matching `.egi` into `InstalledItems`, and `Revision.json` bumped. The
`.egstore\<guid>.manifest` beside the game files must exist; the `.egi`
points at it.

A trap on the way: when the launcher itself is asked to install into an
existing folder, choose the PARENT folder. The launcher appends the game's
mandatory folder name, so pointing it at `...\AlanWake2` prepares
`...\AlanWake2\AlanWake2`, registers an incomplete installation there, and
the real one becomes a "stale duplicate" and is removed.


## What the documentation says

Checked 2026-09-02 against the pages themselves (several Epic help pages
answer 403 to anything but a browser and were read from Wayback captures of
the same article ids; Epic's developer pages were read live).

**No headless launcher.** Epic documents no headless, silent or no-window
start for `EpicGamesLauncher.exe`, and no launcher-level command-line switch
at all. `-silent`, `-launchcontext`, `-noselfupdate`, `-nullrhi` exist in the
binary and nowhere in Epic's material. The only documented "silent" is the
URI parameter below. Epic also states that the launcher coming back up after
a game closes "does not have the feature to disable this behavior"; its
workaround is to uncheck *Minimize To System Tray* and close the launcher
after launching a game.

**The launch URI is official.** Epic's *Protocol Activation* page
(dev.epicgames.com/docs/epic-games-store/protocol-activation) gives exactly
the form Play uses, `com.epicgames.launcher://apps/[SandboxID]%3A[CatalogID]%3A[ArtifactId]?action=launch&silent=true`,
names the three ids (Sandbox = namespace, Catalog = item, Artifact = the
manifest's AppName), lists the actions `launch`, `updatecheck`, `installer`,
keeps the ArtifactId-only form as deprecated but supported, and says of
`silent=true`: it launches the app "without visibly popping up the EGS
Launcher" but is "suggestive": if the launcher decides UI is required
(sign-in, update, prerequisites) it is shown. What a running launcher does
with a second activation is not documented anywhere official.

**Wine does not run the `Run` keys at an automatic boot.** Nothing in the
wineboot man page or the WineHQ wiki says so; the source does. In upstream
`programs/wineboot/wineboot.c` HKLM\Run, HKCU\Run and the Startup folder are
processed only under `if (!init && !restart)`, and the boot that ntdll starts
for a fresh wineserver is always `wineboot.exe --init` (`dlls/ntdll/unix/env.c`,
`run_wineboot`), so they never run there. `RunOnce` does run at every boot and
is deleted afterwards. CrossOver goes further: its wineboot (winecx mirrors,
21 and 25.1) replaces the block with `goto done; /* CodeWeavers hack:
reboot.exe should have handled these already */`, and its `reboot.exe` handles
only `RunOnce`, wininit and file operations per its option strings. The
shipped scripts invoke wineboot only with `--restart` or shutdown flags.
Measured here to match: 637 Steam starts logged by its bootstrapper, none
with the Run key's arguments. The `Steam -silent` and
`EpicGamesLauncher -silent -launchcontext=boot` entries in the bottle's
`Run` key are inert. CodeWeavers documents none of this.

**Cloud saves: after the game closes, by the launcher.** Epic's only timing
statement is in the store's developer test cases: "Close the game. The
Launcher should now sync the cloud save." Nothing official says what a
launcher closed or killed mid-upload does, whether an exit-time upload
happens when no launcher is running, or what the cloud-save log category is
called; the help centre's remedy for a launcher "stuck while cloud syncing"
is End Task. The launcher keeps a `.manifest` per synced artifact under
`AppData\Local\EpicGamesLauncher\Saved\Saves\<EpicAccountID>\<ArtifactID>\`,
which is a documented artifact a future "sync finished" could be measured
from, instead of the quiet-log rule.


## Registering games already on the disk

Options > Epic > *Register games on the disk* lists every folder with an
`.egstore` under the Epic library folders configured above, says whether the
launcher in the bottle already knows it, and writes the launcher's records
for the ones it does not: the `.item` manifest and the helper's `.egi`, with
the revision bumped. The launcher lists them installed at its next start and
takes them over from there (it rewrites the records with its own fields and
offers updates as usual). Nothing is downloaded, deleted or rewritten, and
nothing is written while the bottle is up.

What it reads: the binary build manifest beside the game
(`.egstore/<guid>.manifest`) for the version, executable, command and size,
and the launcher's catalogue cache for the title and the ids. Two joins,
both measured: a DLC's manifest carries the catalogue AppName; a base game
joins by the catalogue's `FolderName`, because its manifest may carry another
build id. A folder with two builds of one app takes the build the catalogue
names, and says so.

Limits. The catalogue cache must exist (open the launcher and sign in once).
A title the cache does not name is listed but not registered. The download
URLs are left empty and the launcher fetches them again on update; that an
update works from an empty list has not been exercised yet.

## Metadata beyond the catalogue cache

The cache holds title, a short description, developer, the box and tall
covers, categories and the store's date-added: no genres, screenshots,
publisher, release date or requirements, and no store slug. The store's
public content endpoint answers without a session, by slug:

    https://store-content.ak.epicgames.com/api/en-US/content/products/<slug>

with long and short descriptions, developer and publisher, gallery and
carousel images, system requirements, languages and, when it is a date, the
release date; and it returns the product's `namespace`, which equals the
catalogue's. RaccoonBot guesses the slug from the title (the plain slug, a
digit split from its word, the title before a colon, edition words dropped,
a trailing number as a numeral: ten of fourteen titles on the first try),
fetches, and keeps a page only when it is the title's: its namespace is the
catalogue's, or its product name is the title with everything but letters
and digits removed (Borderlands 4's page and its owned item are under
different namespaces). A wrong slug is a 404 and the next guess is tried. The page fills the detail
view where Steam's does: description, publisher, screenshots, requirements,
language tags, release date, background. One fetch per title, cached in
`~/Library/Caches/RaccoonBotEpicStoreCache.json`; a miss is kept a week.
Ratings come back empty and `customReleaseDate` is free text, so neither is
shown.


## Two questions that were open, and what closed them

Both raised on 2026-09-03; neither is outstanding now.

### The Epic library the launcher caches IS the account  (settled 2026-09-03)

This was written as an open worry: the "not installed" tab reads Epic titles
from the launcher's catalogue cache, `<AppDataPath>/Catalog/catcache.bin`, and
that file is whatever the launcher wrote at its last signed-in library browse.
It was not known whether that is the same list as what the account owns, so
the tab might have been silently short.

It is the same list, on this machine. Three things say so, and they were
measured rather than assumed:

- All 50 base games in the cache carry an `entitlementName`. That is the mark
  of ownership, not of having browsed past something.
- The launcher rewrote the cache three times across deliberate library
  browses (00:24, 06:16 and 08:38 that day) and it came back byte-identical
  each time: 258 items, 50 of them base games.
- The account owns 50 games, counted by its owner in the launcher's own
  library page.

So nothing is missing, and nothing needs building for it. What the mechanism
still implies is worth keeping in mind: the cache is written by the launcher,
so a machine whose launcher has never signed in and shown the library has no
cache at all, and one that has not done so in a long time has an old one. The
remedy is the cheap one -- open the launcher's library once -- and it is what
RaccoonBot should say if the list ever looks short.

A signing-in route was designed for the case this closed, and then removed
rather than left unused: the user signs in on Epic's own page, which returns
a one-time code, and only the tokens are kept, in the keychain. It is in the
history at commit 325c221 if a future account ever proves the cache
incomplete. The route deliberately NOT taken, and why: the desktop launcher
keeps its own session in `GameUserSettings.ini` under `[RememberMe]`, 1312
bytes under Epic's own encryption rather than Windows' DPAPI, and reading it
would mean decrypting a vendor's credential store with a key taken out of
their client -- an account's safety spent on a convenience.

### A filter by store  (built 2026-09-03)

The library mixes Steam and Epic in one grid with no way to show one. It has
its own button beside the platform filter now, with the same shape: a menu of
toggles, an "All stores" reset, and a badge of glyphs rather than names so the
bar does not resize as you filter. Two decisions, both Mathias's: its own
button rather than a section inside the platform menu, and always visible
rather than appearing only once a second store is configured.

Building it turned up two defects it would otherwise have inherited.

The grid ignored the platform filter. `filteredGames` narrowed the list by
platform and then reassigned `games = allGames` before searching, throwing the
result away; the same filter worked in list view, which goes through `rows`.
Each filter now narrows what the one before it left.

And the Epic titles that are owned and not installed were drawn by nothing.
`allOwnedGames` reached exactly one place -- an `isEmpty` check for the empty
state -- while everything that displays or counts read `ownedGames`, which is
Steam's alone. So they were read off the disk, counted, and never shown.

One thing the filter does not do: the toolbar is not reachable with a
controller. Neither is the platform filter, the tab switcher or the search
field -- the pad's owner stack holds the game grid and the options panel and
nothing else -- so this is not a regression, but it is not covered either.
