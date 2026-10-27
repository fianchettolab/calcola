# Calcola

[Stockfish](https://stockfishchess.org) for Apple platforms, prebuilt and optimised: a
binary Swift package of [StockfishEmbedded](https://github.com/Trickfest/StockfishEmbedded)
by Trickfest, which runs Stockfish in your app's process.

*Calcola* is Italian for "it calculates".

It's part of [Fianchetto Lab](https://github.com/fianchettolab), a set of chess
experiments, and comes as-is. It isn't affiliated with Stockfish or StockfishEmbedded.

## Why

StockfishEmbedded is a source package, so Xcode compiles Stockfish with your app, and in
Debug builds that means unoptimised: searches run about 20 times slower and loading the
net takes seconds. Calcola compiles it once, in Release with `-O3`, and publishes the
result as an XCFramework, so every build of your app gets the optimised engine and none
of them compiles Stockfish.

Nothing else changes. Calcola builds StockfishEmbedded's own package target, with the
sources and settings of its `Package.swift`, unmodified; the API is its `SFEngine`, and
the net stays outside the binary, as in the package.

## Use

Add `https://github.com/fianchettolab/calcola` as a package, pinned to an exact version
(each needs its own net), and the `SFEngine` product to your target. Then follow
StockfishEmbedded's
[quick start](https://github.com/Trickfest/StockfishEmbedded#quick-start-with-swift-package-manager):
bundle the net it names and start the engine with its URL.

```swift
import SFEngine

let url = Bundle.main.url(forResource: SFEngine.defaultNetworkFileName, withExtension: nil)!
let engine = SFEngine(networkFileURL: url) { line in print(line) }
engine.start()
engine.sendCommand("uci")
```

Which StockfishEmbedded is inside, from the framework's Info.plist:

```swift
let info = Bundle(for: SFEngine.self).infoDictionary
info?["CalcolaStockfishEmbeddedVersion"]   // "1.14.0"
info?["CalcolaStockfishEmbeddedCommit"]    // the upstream commit
info?["CFBundleShortVersionString"]        // Calcola's own version
```

| Calcola | StockfishEmbedded | Net |
|---|---|---|
| 0.1.0 | 1.14.0 (`4453510`) | `nn-c9e480e92425.nnue` |

Apple silicon only: iOS 26 (device and simulator) and macOS 26, arm64, as upstream.

## Layout

| Path | What it is |
|---|---|
| `build-xcframework.sh` | Fetches the pinned StockfishEmbedded commit, builds it in Release (`-O3`) for iOS, the iOS simulator and macOS, and packs `build/SFEngine.xcframework` |
| `release.sh` | Builds, tests, zips and tags a release, writing its version and checksum into `Package.swift` |
| `Package.swift` | The `SFEngine` binary target: the release's zip, or a local build when there is one |
| `Tests/CalcolaTests/` | Runs the built framework on the Mac: its upstream keys, a mate in one, and the speed of an optimised build |

## Building

You need Xcode and git:

```bash
./build-xcframework.sh
build/StockfishEmbedded/Scripts/download-nnue.sh   # the net, for the tests (113 MB)
swift test
```

A build takes about 45 s. Without the net, the engine test is skipped.

## Licence

GPL-3.0, like Stockfish and StockfishEmbedded. Each framework carries StockfishEmbedded's
licence, Stockfish's `Copying.txt` and its `AUTHORS`. The exact source of every release is
the StockfishEmbedded commit named above and in its release notes, built by the scripts
here; an app that ships it must offer its users that source too.

Stockfish's code includes Unix-domain sockets (`shm_unix.h`, to share memory between
Stockfish processes on one machine); nothing in it uses the network.
