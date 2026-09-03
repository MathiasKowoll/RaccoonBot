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
