<img width="80" height="80" alt="RaccoonBot" src="Logo.icon/Assets/Image.png" />

# RaccoonBot

A Steam launcher for macOS that runs Windows games through CrossOver — and fixes
the ones whose cutscenes do not play.

> **RaccoonBot is not a replacement for anything. It needs CrossOver, and it
> needs it installed and licensed by you.**
>
> It is an enhancement layer on two other projects: it will not run a single
> game without [CrossOver](https://www.codeweavers.com/crossover), and its
> entire interface is [Procyon](https://github.com/italomandara/Procyon). What
> RaccoonBot adds is the video layer on top.

CrossOver, by CodeWeavers, is what actually runs the games — it is a commercial
Wine distribution, you buy it, and RaccoonBot neither includes nor replaces it.

Procyon, by Italo Mandara, is the launcher: the library, the bottle handling,
the per-game options, the CrossOver patching, the whole interface you see in the
screenshots below. RaccoonBot is a fork of it.

What RaccoonBot adds is one thing: a video-decoding layer and a catalogue of
per-title fixes, for games that install correctly under CrossOver and then show
a black screen, a green screen, or exit when the first cutscene starts. If your
games already play their cutscenes, you want Procyon, not this.

---

## What it does

**Runs your Steam library.** Windows titles through a patched copy of CrossOver,
macOS titles natively. It reads Steam's own files on disk, so the library is
drawn before it asks the network for anything — and stays drawn if the network
never answers.

**Patches CrossOver for you.** It copies your CrossOver into a separate
application and adds DXMT, an updated MoltenVK, and Apple's Game Porting Toolkit
(D3DMetal). Your original CrossOver is not modified.

**Fixes cutscenes.** This is the part that is not in Procyon. Many Windows games
run fine under CrossOver until a video starts: Wine's media pipeline has no
decoder for the format, and the game either plays audio over a blank picture or
exits. RaccoonBot stages the missing GStreamer decoders per engine and applies
per-title fixes where a decoder alone is not enough.

**Installs what is missing.** It reports whether the GStreamer framework is
present and offers to download the right version for your CrossOver, and it can
apply every fix your library needs in one pass.

**Tells you before you are surprised.** A title that needs its fix is marked in
the library and warned about *before* it launches, not after the cutscene fails.

---

## Requirements

| | |
|---|---|
| macOS | **15 or later**, Apple Silicon. The build targets `arm64` only |
| [CrossOver](https://www.codeweavers.com/crossover) | 26.x or 27.x. You buy and install it yourself; RaccoonBot does not include it |
| [GStreamer](https://gstreamer.freedesktop.org/download/) | The universal macOS framework. RaccoonBot checks for it and offers to fetch it |
| Steam | Installed inside a CrossOver bottle, and signed in |

Apple's Game Porting Toolkit is optional and supplied by you. RaccoonBot copies
it into the patched CrossOver if you point it at one; it does not redistribute
it.

---

## Installing RaccoonBot

Download the `.app` from
[Releases](https://github.com/MathiasKowoll/RaccoonBot/releases), move it to
`/Applications`, and open it.

**macOS will refuse the first time.** RaccoonBot is signed ad-hoc and is not
notarised, so Gatekeeper blocks it. This is expected and the fix takes ten
seconds — see [the FAQ](#macos-says-raccoonbot-cannot-be-opened) below.

---

## Using it

### The library

![The library, list view](docs/images/01-list.png)

Three tabs:

- **Installed** — what you can play right now
- **Not installed** — everything else Steam knows you have, with an Install
  button that hands the job to Steam's own dialog
- **All** — both at once

Two views, and the choice is remembered. The **list** is the one above: sortable
by name, platform, size, hours played and when you last played. The **grid**
shows cover art. `Installed` is the platform a title is installed *as*;
`Available` is what it ships *for* — a game can offer three and be installed as
one.

![The library, grid view](docs/images/02-grid.png)

Search filters the list you are looking at, and the count beside the field tells
you how much of it you are seeing.

### A game's page

![A game's detail page](docs/images/05-game-detail.png)

Click a cover or a row and you get the store page for that title — description,
genres, release date, and what it is available for. From here you can play it,
open its options, or reveal its folder. For a title you have not installed, the
same page appears with an Install button instead.

### Settings

![Application settings](docs/images/03-app-settings.png)

This is where you point RaccoonBot at CrossOver, choose a bottle, and see
whether GStreamer is installed and current. **Patch all** applies every fix your
installed library needs in one pass — it checks each title is really there
first, and skips anything you have chosen to leave alone.

### Per-game options

![Per-game options](docs/images/04-game-settings.png)

Every title carries its own graphics backend, environment variables and launch
options. **Auto configure** installs that title's fix and sets the options it is
known to need, in one action.

---

## The fixes

RaccoonBot downloads a catalogue from
[MacGameVideoFix](https://github.com/MathiasKowoll/MacGameVideoFix) at run time —
currently **17 titles** across **11 installers** — and verifies its checksum
before unpacking. It is not bundled, so a fix can ship without a new release of
the application.

### The codecs

Wine's `winegstreamer` asks GStreamer to decode a game's video. The official
GStreamer framework carries the pieces, but CrossOver's own copy does not always
have the ones a game needs. RaccoonBot stages two plugins per engine:

| Plugin | What it decodes |
|---|---|
| `libgstlibav` | The FFmpeg-backed decoders — WMV2, H.264, VP9 and the rest |
| `libgstmatroska` | The Matroska/WebM container, which several Unreal Engine titles use |

They are staged into a per-engine directory with FFmpeg alongside, and
CrossOver's own GStreamer core is symlinked rather than copied, so exactly one
core is loaded per process.

### What the per-title fixes actually do

The catalogue covers four distinct failures. They are different problems and the
fixes are not interchangeable:

- **No decoder.** *Nioh*, *Nioh 2*, *Nioh 3*, *Persona 5 Strikers*, *Devil May
  Cry 5* — the cutscene runs with sound and no picture. The staged codec is the
  whole fix for these; nothing is installed in the game folder.
- **Media Foundation reports nothing.** *NINJA GAIDEN 4* asks the system what
  can decode VP9, is told nothing can, and exits. It needs the decoder count to
  be answered honestly.
- **Direct3D interfaces D3DMetal lacks.** *DYNASTY WARRIORS: ORIGINS*, *Wo Long:
  Fallen Dynasty*, *Mortal Shell 2*, *Beast of Reincarnation*, the *Life is
  Strange* titles — a bridge library stands in for the calls the player makes.
- **Not about video at all.** *TMNT: Splintered Fate* and *Tormented Souls 2*
  each make one D3D12 call that ends the process; the fix guards that call.

*KINGDOM HEARTS* is its own case: cutscenes play with sound over a solid green
picture, because the luma and chroma planes are handled separately.

---

## FAQ

### macOS says RaccoonBot cannot be opened

Because it is not notarised. Apple charges for a developer account, and this is
a free project.

Nothing is wrong with the download — macOS refuses any application it cannot
trace to a paid Apple developer identity, whatever the application does. To open
it:

1. Try to open RaccoonBot once and dismiss the warning
2. **System Settings → Privacy & Security**
3. Scroll to Security. There is a line about RaccoonBot being blocked, and an
   **Open Anyway** button
4. Click it, then confirm

You only do this once. On older macOS versions, right-clicking the app and
choosing **Open** does the same thing; on recent versions it does not, and
System Settings is the only route.

If that makes you uncomfortable, the honest answer is to build it yourself —
`./build-local.sh` produces the same application from the source in this
repository, and an application you compiled needs no permission from anyone.

### Does it modify my CrossOver?

No. It copies CrossOver into a separate patched application and modifies the
copy. Your CrossOver keeps working exactly as it did, and you can delete the
patched copy at any time.

### Do I have to buy CrossOver?

Yes. It is commercial software from CodeWeavers and RaccoonBot does not include
it, replace it, or work without it.

### Why do I have to install GStreamer separately?

Because bundling it would mean redistributing it, which brings obligations this
project would rather not take on when the official installer is one click away.
RaccoonBot tells you which version fits your CrossOver and opens the download.

### A game still shows a black screen

Open its options and check the fix is applied. If it is, the title may need a
decoder that is not staged yet, or a fix that does not exist yet — open an issue
with the game and what you see, and it can be looked at.

### Does it send my library anywhere?

No. The library is read from Steam's own files on your disk. The only requests
RaccoonBot makes are to Steam's public store endpoint, for a title's name and
cover art — no key, no account, no cookies — and to GitHub, for the fixes
bundle. It does not use the metadata proxy Procyon uses, and cannot: that is one
person's server and his quota.

### Will you upstream this to Procyon?

Some of it should be. `UPSTREAM.md` in this repository records which commits fix
bugs in Procyon itself and which are only ours. Nothing has been offered yet.

---

## Credits

RaccoonBot is a fork, and most of what it does was somebody else's work first.

### Procyon and CXPatcher

**[Italo Mandara](https://github.com/italomandara)** wrote
[Procyon](https://github.com/italomandara/Procyon), which is the launcher this
is built on — the library, the bottle handling, the per-game options, the whole
interface — and
[CXPatcher](https://github.com/italomandara/CXPatcher) before it, which is where
the CrossOver-patching approach comes from. Without those two this project would
not exist; it would be a shell script.

### WineVideo

**[Jfishin/winevideo](https://github.com/Jfishin/winevideo)** — "Drop-in
VP9/WebM video support + d3dmetal crash fix for CrossOver 26.2 (Apple Silicon)".
The same problem RaccoonBot's video layer exists to solve, solved first and
solved directly. Worth reading if you want the fix without a launcher around it.

It declares no licence, so nothing of it is reused here; the credit is for the
work and for showing the shape of the problem.

### Carried over from Procyon's own credits

- **[@Lifeisawful](https://github.com/Lifeisawful)** — rosettax87, which is how
  32-bit titles run at a usable speed
- **[@Gcenx](https://github.com/Gcenx)** — patched Wine components and
  dxvk-macos
- **[@nastys](https://github.com/nastys)** — the UE4 MoltenVK hack

<!-- LICENCES: pending verification -->

---

## Building it

```bash
git clone https://github.com/MathiasKowoll/RaccoonBot.git
cd RaccoonBot
./build-local.sh
```

The application lands in `build/`. Signing is ad-hoc, so no Apple developer
account is needed to build or run your own copy.

Tests:

```bash
xcodebuild -project RaccoonBot.xcodeproj -scheme RaccoonBot -destination 'platform=macOS' test
```

---

## Licence

GPL-3.0-or-later. See [LICENSE.txt](LICENSE.txt).

Third-party attribution is in [CREDITS.md](CREDITS.md).
