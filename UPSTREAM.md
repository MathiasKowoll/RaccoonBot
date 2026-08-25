# Relationship with upstream

This fork is a product, not a patch queue. It is not trying to become
italomandara/Procyon, and it does not need to be merged there to be useful.

But several things found while building on it are defects of *Procyon*, not of
the integration, and they affect anyone using it. This file records which is
which, while the reasoning is still fresh — deciding it later is archaeology.

Nothing here has been offered upstream. That is a decision, not an oversight:
no pull request until the application is complete.

## How the branches relate

    upstream/main       abandoned, tip 2026-07-03, and it does NOT contain the
                        work in cx-26-1 — they are separate lineages, so never
                        merge it into anything here
    upstream/cx-26-1    the branch this is built on; still receiving commits
    cx-26-1             kept pristine, tracking upstream. Two uses: pulling
                        their changes in, and being the base a pull request is
                        cut from
    VideoFixIntegration our line

Keeping `cx-26-1` untouched is what makes both directions cheap. A topic branch
off it carrying a curated subset is a reviewable pull request; our own branch
never would be, because it also carries a local build configuration and an
entire integration with another project.

## Would help upstream

These are bugs in Procyon that exist without any of our work, each found by
running it rather than reading it. Cherry-picking any of them onto a branch
based on `upstream/cx-26-1` should be close to clean.

| Commit | What it fixes upstream |
|---|---|
| `6fd6fef` | Five `as!` on Info.plist keys that are not in Info.plist. A clone without the author's gitignored `Config.xcconfig` crashes before a window appears — which is every clone. |
| `d96e3c8` | `LIB_ROOT` is the constant `"lib64"`, and CrossOver 27 has no `lib64`. Patching a 27 engine writes every path into a directory that does not exist, and the exception dies in a mute `catch`: the copy comes out with no DXMT, no bottle redirection and no marker, silently. |
| `8d08952` (part) | `winegstreamer.so` and `winedmo.so` carry `LC_RPATH @loader_path/../../../lib64/GStreamer.framework/Libraries`. Copied over a 27 engine, Wine's bridge to GStreamer resolves its libraries to nothing. |
| `90c3aec` (part) | `stripEnvsInCXBottleConfigFile` truncates the whole `[EnvironmentVariables]` section — no whitelist, no backup, and it assumes that section is last in the file. It removes keys other tools rely on. |
| `d261619` (idea) | `safeShell` sends both streams to `nullDevice` and returns without `waitUntilExit`, so a script that failed halfway is indistinguishable from one that succeeded. |
| `d0aef9b` (part) | `--bottle` takes a name resolved under whichever root the engine uses. With two bottles whose names differ only in case — and macOS does not distinguish — a launch can go to the wrong one in silence. |
| `f642990` (idea) | The GitHub API is read with `as!` on `tag_name`. A rate limit answers without that field, and the anonymous limit is sixty an hour. |

## Ours only

Not upstream material, and not because it is unfinished: it is a different
product decision. Everything under `Procyon/Util/MGVF*`, `GStreamerStatus`,
`GStreamerInstall`, the tests, `build-local.sh` and `NOTES-mgvf.md`. Also
`8d08952`'s removal of the GStreamer install: upstream replaces the engine's
whole stack on purpose, and we deliberately do not.

## Staying in step

`git fetch upstream && git merge upstream/cx-26-1` on this branch, occasionally.
Their branch is alive; the longer the gap, the less cheap it gets. And never
`upstream/main` — see above.
