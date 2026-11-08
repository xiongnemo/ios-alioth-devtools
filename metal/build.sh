#!/bin/bash
# Every metal/*.metal -> <name>.metallib, plus <name>.ll (the AIR as text, for whoever translates it), with Xcode's
# Metal compiler, for iOS 16 (the AIR an iOS 16 device can read).
#   ./build.sh
# OUT=DIR (default ../build/metal); STD (default metal3.0) and MIN (default 16.0) for the language and the oldest iOS.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$HERE/../build/metal}
STD=${STD:-metal3.0}
MIN=${MIN:-16.0}
mkdir -p "$OUT"
# (Xcode 26 and later download the Metal compiler separately)
if ! xcrun -sdk iphoneos metal --version >/dev/null 2>&1; then
	xcodebuild -downloadComponent MetalToolchain
fi
xcrun -sdk iphoneos metal --version
for f in "$HERE"/*.metal; do
	n=$(basename "$f" .metal)
	xcrun -sdk iphoneos metal -std="$STD" -mios-version-min="$MIN" -c "$f" -o "$OUT/$n.air"
	xcrun -sdk iphoneos metal -std="$STD" -mios-version-min="$MIN" -S -emit-llvm "$f" -o "$OUT/$n.ll"
	xcrun -sdk iphoneos metallib "$OUT/$n.air" -o "$OUT/$n.metallib"
	rm "$OUT/$n.air"
	echo "build.sh: $n.metallib ($(wc -c < "$OUT/$n.metallib") bytes)"
done
