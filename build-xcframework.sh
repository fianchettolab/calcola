#!/usr/bin/env bash
# Builds build/SFEngine.xcframework (iOS device, iOS simulator, macOS; arm64) from the
# StockfishEmbedded release pinned below, optimised (-O3), as a dynamic framework. Needs
# Xcode and git.
#
# StockfishEmbedded's own Package.swift decides the sources and defines: this script only
# fetches it, compiles its SFEngine target in Release and packs the result. The net stays
# outside (NNUE_EMBEDDING_OFF), as in the package: apps pass its URL to SFEngine.
set -euo pipefail

# The upstream release, and the commit its tag points to.
upstream_version="1.14.0"
upstream_commit="4453510fb61d86cd491b74329baa86f23c519cb0"
upstream_repo="https://github.com/Trickfest/StockfishEmbedded"

# Written into the frameworks' Info.plist; release.sh passes the release's version.
version="${CALCOLA_VERSION:-0.0.0}"

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"

out="build"
src="$out/StockfishEmbedded"
framework="$out/SFEngine.xcframework"

# Matches StockfishEmbedded's platforms (iOS 26, macOS 26).
ios_minimum="26.0"
macos_minimum="26.0"

# The pinned commit, fetched once; anything else there is replaced. Fetched by commit
# rather than tag, so a moved tag can't change what's built.
if [[ "$(git -C "$src" rev-parse HEAD 2>/dev/null)" != "$upstream_commit" ]]; then
    rm -rf "$src"
    git init --quiet "$src"
    git -C "$src" fetch --quiet --depth 1 "$upstream_repo" "$upstream_commit"
    git -C "$src" -c advice.detachedHead=false checkout --quiet FETCH_HEAD
fi
# xcodebuild prefers their Xcode project (the embedded-net targets) over the package, so
# the clone keeps only the package. Restored by git checkout.
rm -rf "$src/StockfishEmbedded.xcodeproj"

# platform name, xcodebuild destination, products folder, SDK, clang target
slices=(
    "ios|generic/platform=iOS|Release-iphoneos|iphoneos|arm64-apple-ios$ios_minimum"
    "ios-simulator|generic/platform=iOS Simulator|Release-iphonesimulator|iphonesimulator|arm64-apple-ios$ios_minimum-simulator"
    "macos|generic/platform=macOS|Release|macosx|arm64-apple-macos$macos_minimum"
)

notices=(
    "$src/LICENSE:LICENSE-StockfishEmbedded.txt"
    "$src/ThirdParty/Stockfish/Copying.txt:COPYING-Stockfish.txt"
    "$src/ThirdParty/Stockfish/AUTHORS:AUTHORS-Stockfish.txt"
)

# The framework's Info.plist. The upstream keys tell apps which StockfishEmbedded is
# inside.
info_plist() {
    local platform="$1" plist="$2"
    /usr/libexec/PlistBuddy -c "Clear dict" "$plist" >/dev/null 2>&1 || true
    local entries=(
        "CFBundleDevelopmentRegion string en"
        "CFBundleExecutable string SFEngine"
        "CFBundleIdentifier string org.fianchettolab.calcola.SFEngine"
        "CFBundleInfoDictionaryVersion string 6.0"
        "CFBundleName string SFEngine"
        "CFBundlePackageType string FMWK"
        "CFBundleShortVersionString string $version"
        "CFBundleVersion string $version"
        "CalcolaStockfishEmbeddedVersion string $upstream_version"
        "CalcolaStockfishEmbeddedCommit string $upstream_commit"
    )
    case "$platform" in
        ios) entries+=("MinimumOSVersion string $ios_minimum" "CFBundleSupportedPlatforms array") ;;
        ios-simulator) entries+=("MinimumOSVersion string $ios_minimum" "CFBundleSupportedPlatforms array") ;;
        macos) entries+=("LSMinimumSystemVersion string $macos_minimum" "CFBundleSupportedPlatforms array") ;;
    esac
    for entry in "${entries[@]}"; do
        /usr/libexec/PlistBuddy -c "Add :$entry" "$plist" >/dev/null
    done
    local supported
    case "$platform" in
        ios) supported="iPhoneOS" ;;
        ios-simulator) supported="iPhoneSimulator" ;;
        macos) supported="MacOSX" ;;
    esac
    /usr/libexec/PlistBuddy -c "Add :CFBundleSupportedPlatforms:0 string $supported" "$plist" >/dev/null
}

args=()
for slice in "${slices[@]}"; do
    IFS="|" read -r platform destination products sdk target <<<"$slice"
    derived="$out/derived/$platform"
    echo "Building $platform…"
    # Coverage off: Xcode would otherwise instrument the package's code.
    (cd "$src" && xcodebuild build -scheme StockfishEmbedded -configuration Release \
        -destination "$destination" -derivedDataPath "$here/$derived" \
        ARCHS=arm64 ONLY_ACTIVE_ARCH=NO GCC_OPTIMIZATION_LEVEL=3 CLANG_ENABLE_CODE_COVERAGE=NO \
        >"$here/$out/$platform.log" 2>&1) || {
        echo "xcodebuild failed for $platform; see $out/$platform.log." >&2
        exit 1
    }
    object="$derived/Build/Products/$products/SFEngine.o"

    bundle="$out/frameworks/$platform/SFEngine.framework"
    rm -rf "$bundle"
    if [[ "$platform" == macos ]]; then
        # macOS frameworks are versioned bundles.
        contents="$bundle/Versions/A"
        mkdir -p "$contents/Headers" "$contents/Modules" "$contents/Resources"
        ln -s A "$bundle/Versions/Current"
        for link in SFEngine Headers Modules Resources; do
            ln -s "Versions/Current/$link" "$bundle/$link"
        done
        install_name="@rpath/SFEngine.framework/Versions/A/SFEngine"
        plist="$contents/Resources/Info.plist"
        notice_dir="$contents/Resources"
    else
        contents="$bundle"
        mkdir -p "$contents/Headers" "$contents/Modules"
        install_name="@rpath/SFEngine.framework/SFEngine"
        plist="$contents/Info.plist"
        notice_dir="$contents"
    fi

    xcrun --sdk "$sdk" clang++ -dynamiclib -target "$target" \
        -isysroot "$(xcrun --sdk "$sdk" --show-sdk-path)" \
        "$object" -o "$contents/SFEngine" -install_name "$install_name" \
        -framework Foundation -lobjc -Wl,-dead_strip
    xcrun strip -x "$contents/SFEngine"

    cp "$src/Sources/SFEngine/include/SFEngine.h" "$contents/Headers/"
    cat >"$contents/Modules/module.modulemap" <<'EOF'
framework module SFEngine {
    umbrella header "SFEngine.h"
    export *
    module * { export * }
}
EOF
    info_plist "$platform" "$plist"
    for notice in "${notices[@]}"; do
        cp "${notice%%:*}" "$notice_dir/${notice##*:}"
    done
    args+=(-framework "$bundle")
done

rm -rf "$framework"
xcodebuild -create-xcframework "${args[@]}" -output "$framework" >/dev/null

echo "Built $framework ($(du -sh "$framework" | cut -f1)): StockfishEmbedded $upstream_version, -O3."
