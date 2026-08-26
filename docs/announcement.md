# RaccoonBot — a CrossOver launcher that fixes the cutscenes

If you play Windows games on a Mac through CrossOver, you know the shape of this
problem. The game installs. It launches. It runs well. Then the first cutscene
starts and you get a black screen with audio, or a green screen with audio, or
the process simply exits and drops you back to the desktop.

It is not a graphics driver problem and it is not your Mac. Wine hands video
decoding to GStreamer, and the decoder the game asks for is often not there.
Some games handle that gracefully and play a blank rectangle. Some ask Media
Foundation what can decode VP9, are told nothing can, and quit on the spot.

RaccoonBot exists to fix that specific thing.

## What it is

It is a fork of [Procyon](https://github.com/italomandara/Procyon) by Italo
Mandara, which is a Steam launcher for macOS that runs Windows games through
CrossOver. Procyon is the whole interface: the library, the bottle handling, the
per-game options, the CrossOver patching. I did not write any of that, and
RaccoonBot would be a shell script without it.

What RaccoonBot adds is a video layer on top: the missing decoders, staged where
Wine will actually find them, plus a catalogue of per-title fixes for the cases
where a decoder alone is not enough.

**It needs CrossOver.** It does not replace it, include it, or work without it.
CrossOver is commercial software from CodeWeavers and you buy it yourself. If
your games already play their cutscenes fine, you want Procyon, not this.

## The fixes

There is a catalogue of 17 titles at the moment, downloaded at runtime rather
than baked into the app, so fixes can ship without a new release. They cover
four genuinely different failures — they are not interchangeable, and calling
them all "video fixes" hides more than it explains:

**No decoder at all.** *Nioh*, *Nioh 2*, *Nioh 3*, *Persona 5 Strikers*, *Devil
May Cry 5*. The cutscene runs with sound and no picture. Staging the codec is
the entire fix — nothing gets written into the game folder.

**Media Foundation reports zero.** *NINJA GAIDEN 4* asks the system what can
decode VP9, is told nothing can, and exits before you see anything. It needs
that question answered honestly.

**Direct3D interfaces D3DMetal does not implement.** *DYNASTY WARRIORS: ORIGINS*,
*Wo Long: Fallen Dynasty*, *Mortal Shell 2*, *Beast of Reincarnation*, the *Life
is Strange* titles. A small bridge library stands in for the calls the video
player makes.

**Not about video at all.** *TMNT: Splintered Fate* and *Tormented Souls 2* each
make a single D3D12 call that kills the process. The fix guards that one call.

*KINGDOM HEARTS* is its own case — cutscenes play with sound over a solid green
picture, because the luma and chroma planes are handled separately.

Two GStreamer plugins do the general work: `libgstlibav` for the FFmpeg-backed
decoders (WMV2, H.264, VP9 and the rest) and `libgstmatroska` for the
Matroska/WebM container several Unreal Engine titles use. They are staged per
engine, with CrossOver's own GStreamer core symlinked rather than copied, so
exactly one core loads per process.

## The rest of it

Since I was in there anyway, a fair amount of the launcher got worked on too.

**The library is read from disk first.** Your installed games, their names,
their cover art and how long you have played them all come from Steam's own
files. The library is drawn before anything touches the network, and stays drawn
if the network never answers. Steam's public store endpoint fills in
descriptions afterwards, one title at a time, paced so it cannot get your IP
throttled — no API key, no account, no third-party proxy.

**Three tabs**: what is installed, what you own but have not installed, and both
together. Install hands the job to Steam's own dialog through the `steam://`
protocol; for a title that ships for both platforms it asks which build you
want first, because the Windows one runs in the bottle where the fixes apply and
the macOS one does not.

**Two views.** A grid of cover art, and a sortable list — name, platform, size,
hours played, last played. `Installed` is the platform a title is installed *as*;
`Available` is what it ships *for*, which is a different question. The choice of
view is remembered.

**Patch all.** One button that applies every fix your installed library needs,
after checking each title is actually on disk — an entry for a game on an
unmounted external drive is a path that is not there, and half-downloaded games
have no executable to patch yet.

**It warns you before, not after.** A title that needs its fix is marked in the
library and warned about *before* it launches, rather than after the cutscene
fails. It asks rather than acts: applying a fix renames a file inside your game
folder, and doing that quietly behind a Play button is not a thing to do.

**GStreamer status.** It tells you whether the framework is installed, whether
it matches your CrossOver, and offers the right version to download when it does
not.

## Requirements

- macOS 15 or later, Apple Silicon
- CrossOver 26.x or 27.x, licensed by you
- The GStreamer macOS framework — the app checks for it and points you at the
  right version
- Steam, installed inside a bottle and signed in

D3DMetal and the Wine components for the 32-bit path come with the app.

## Honest limits

**It is a pre-release.** It works on my machine and has not been run anywhere
else. Version 0.1.0, and the number is deliberate.

**It is built for macOS 15 but has only been tested on 26.** It compiles
cleanly against 15 with no availability errors, but nobody has run it on an
older machine. If you do, I would like to hear how it went either way.

**macOS will refuse to open it the first time.** It is signed ad-hoc and not
notarised — Apple charges for a developer account and this is a free project.
Open it once, dismiss the warning, then System Settings → Privacy & Security →
**Open Anyway**. Once only. On recent macOS, right-click → Open no longer works;
System Settings is the only route. If that does not sit right with you, the
source is there and `./build-local.sh` produces the same application.

**17 titles is not many.** It is the ones that have actually been debugged, one
at a time, by watching them fail. If a game of yours shows a black screen where
a cutscene should be, that is worth an issue — the failure mode is usually one
of the four above and the fix is usually small.

## Credit

Italo Mandara wrote Procyon and CXPatcher, which is everything this is built on.
[Jfishin/winevideo](https://github.com/Jfishin/winevideo) solved the same video
problem first, and directly, without a launcher wrapped around it — worth
reading if that is what you want. Procyon's own credits carry through:
@Lifeisawful for rosettax87, @Gcenx for the patched Wine components and
dxvk-macos, @nastys for the UE4 MoltenVK hack. And CodeWeavers, whose CrossOver
does the actual work of running the games.

**Repository and downloads:** https://github.com/MathiasKowoll/RaccoonBot

GPL-3.0, like Procyon. Not affiliated with CodeWeavers, Apple, Valve, or any
game publisher named above.
