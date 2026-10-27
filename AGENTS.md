# AGENTS.md

Calcola is part of Fianchetto Lab. Handoff notes for anyone (human or agent) picking up
Calcola cold: how to work here and the decisions already settled with the owner. What the
package does, its layout and how to build it are in [README.md](README.md); this file
doesn't repeat them.

## Working with the owner

- **Advise before applying** anything non-trivial (new dependencies, a different build,
  structural changes): lay out the options and a recommendation, then wait for a
  go-ahead.
- **Let the owner test before committing.** Don't commit until they say so.
- **Releases and pushes need a go-ahead.** A release is public the moment it's created,
  and apps download it.
- **Record settled decisions here**, as the current state, not as a history of changes.
- **Commits** use the owner's GitHub noreply address (set in the global git config); never
  their personal email.

## Settled decisions

- **Why it exists:** a source package of Stockfish builds unoptimised in an app's Debug
  builds (Xcode applies the package's own settings, and a project-level optimisation level
  doesn't reach it): about 20 times slower, with seconds to load the net. A prebuilt
  binary is optimised everywhere and never recompiled.
- **StockfishEmbedded's build, not ours.** The script builds its `SFEngine` package
  target with `xcodebuild` in Release, so its `Package.swift` stays the only list of
  sources and defines. Calcola adds `-O3` (as upstream Stockfish and StockfishEmbedded's
  own Release libraries), turns off Xcode's code coverage, and links and packs the result.
  No copy of their source is committed; the script fetches the pinned commit.
- **The maintained path:** the net stays outside the binary (`NNUE_EMBEDDING_OFF`), as in
  their package. Their Xcode project's library targets, which embed the net, are what
  they call legacy; the script removes that project from its clone so `xcodebuild` builds
  the package.
- **Pinned by commit:** `upstream_version` and `upstream_commit` at the top of
  `build-xcframework.sh`; the commit is fetched directly, so a moved tag can't change
  what's built.
- **A dynamic framework** in the XCFramework, linked against the system's libc++, so apps
  need no linker flags. Versioned bundle on macOS, flat on iOS.
- **Versions are Calcola's own**, semantic, from 0.1.0. Each framework's Info.plist names
  the upstream (`CalcolaStockfishEmbeddedVersion`, `CalcolaStockfishEmbeddedCommit`), so an
  app can show "Calcola 0.1.0 (StockfishEmbedded 1.14.0)" from the binary it linked. The
  README's table lists each release's upstream and net.
- **Apple silicon only:** iOS device, iOS simulator and macOS, arm64; iOS 26 and macOS 26,
  as upstream (NEON).
- **`Package.swift` picks the binary:** a local `build/SFEngine.xcframework` when there
  is one, otherwise the release URL with its checksum, both written by `release.sh`.
- **Licence:** GPL-3.0. Each framework carries StockfishEmbedded's `LICENSE`, Stockfish's
  `Copying.txt` and `AUTHORS`.

## Upgrading StockfishEmbedded

1. Set `upstream_version` and `upstream_commit` in `build-xcframework.sh` (the commit the
   release's tag points to).
2. `./build-xcframework.sh`, `build/StockfishEmbedded/Scripts/download-nnue.sh`,
   `swift test`.
3. Add the release's row to the README's table, with the net their `Docs/Provenance.md`
   names.
4. Release as below, with a new minor version.

## Releasing

1. On a clean `main`: `./release.sh <version>`. It builds, tests with the net, zips,
   writes the version and checksum into `Package.swift`, writes `build/release-notes.md`,
   commits "Release <version>" and tags.
2. With the owner's go-ahead: `git push origin main <version>`, then
   `gh release create <version> build/SFEngine.xcframework.zip --title <version> --notes-file build/release-notes.md`.
3. Users raise their exact pin, and change their net if the upstream changed it.

## Gotchas

- **SwiftPM caches the manifest:** after creating or deleting `build/`, touch
  `Package.swift` (or reset package caches in Xcode) before the switch between the local
  build and the release takes effect.
- **The engine is one per process** (StockfishEmbedded's rule), so the tests are
  serialized and start it once.
