#!/usr/bin/env bash
# Prepares release <version>: builds the XCFramework, tests it with the net, zips it,
# writes the version and the zip's checksum into Package.swift, commits and tags. Then push
# the tag and upload the zip:
#   git push origin main <version>
#   gh release create <version> build/SFEngine.xcframework.zip --title <version> --notes-file build/release-notes.md
set -euo pipefail

version="${1:?usage: release.sh <version>, e.g. 0.1.0}"
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "The working tree has changes; commit them first." >&2
    exit 1
fi

CALCOLA_VERSION="$version" ./build-xcframework.sh
# A release is never untested: the tests need the net, which their script downloads
# (or reuses) and checks.
build/StockfishEmbedded/Scripts/download-nnue.sh
swift test

zip="build/SFEngine.xcframework.zip"
rm -f "$zip"
# Without resource forks and extended attributes: ditto would store them as ._ files,
# which Xcode then finds in the framework's headers.
(cd build && ditto -c -k --norsrc --noextattr --keepParent SFEngine.xcframework SFEngine.xcframework.zip)
if unzip -l "$zip" | grep -q '/\._'; then
    echo "$zip contains ._ metadata files; not releasing it." >&2
    exit 1
fi
checksum="$(swift package compute-checksum "$zip")"

upstream_version="$(sed -n 's/^upstream_version="\(.*\)"/\1/p' build-xcframework.sh)"
upstream_commit="$(sed -n 's/^upstream_commit="\(.*\)"/\1/p' build-xcframework.sh)"
cat >build/release-notes.md <<EOF
StockfishEmbedded $upstream_version ($upstream_commit), built with -O3 as a dynamic framework.

Needs the net \`$(git -C build/StockfishEmbedded show HEAD:ThirdParty/Stockfish/src/evaluate.h \
    | sed -nE 's/^#define[[:space:]]+EvalFileDefaultName[[:space:]]+"([^"]+)".*/\1/p')\`.
Source: https://github.com/Trickfest/StockfishEmbedded/tree/$upstream_commit
EOF

sed -i '' "s/^let release = .*/let release = (version: \"$version\", checksum: \"$checksum\")/" Package.swift

git add Package.swift
git commit -m "Release $version"
git tag "$version"

echo "Tagged $version ($(du -h "$zip" | cut -f1), checksum $checksum)."
echo "Next: git push origin main $version"
echo "      gh release create $version $zip --title $version --notes-file build/release-notes.md"
