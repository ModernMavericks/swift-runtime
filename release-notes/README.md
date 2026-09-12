# Release notes

One OPTIONAL file per release, named `<full-version>.md` (e.g. `6.3.3-mavericks.5.md`). Its content
is committed prose that `release-notes.sh` (the shared shipyard generator, called from
`.github/workflows/release.yml`) slots in verbatim, ahead of its own auto-generated `### What
changed` / `### Build ingredients` / footer sections. Do not add your own `## ` title line here --
the generator emits the title itself.

A repackage (an ingredient bump, no new Swift version) normally has no file here at all: that is a
normal case, not a failure. The generator composes the whole body -- naming which ingredient moved
-- on its own.

The generated file (`dist/RELEASE_NOTES.md`, built fresh every run) is what actually ships: it is
both the Sparkle appcast `<description>` and the GitHub Release body, the same bytes by construction.
