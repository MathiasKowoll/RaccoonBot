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
