#!/bin/bash
# FlutterCheck.ipa: a Flutter application (lib/main.dart, shaders/) for iOS arm64, built by the Flutter SDK on macOS
# with Xcode, signed ad hoc (codesign -s -), not by Apple: for an iOS that runs such applications (the K40 port).
# Bundle id com.anzupop.com.ios.fluttercheck. `flutter` on PATH; OUT=DIR (default build/flutter) gets the .ipa.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$HERE/../build/flutter}
WORK=$(mktemp -d)
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

flutter --version
# (the iOS project around it is Flutter's own template, made afresh: only the Dart side and the shader are ours)
flutter create --org com.anzupop.com.ios --project-name fluttercheck --platforms ios "$WORK/fluttercheck"
cd "$WORK/fluttercheck"
cp "$HERE/pubspec.yaml" pubspec.yaml
rm -rf lib
cp -R "$HERE/lib" lib
cp -R "$HERE/shaders" shaders
rm -rf test
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Flutter Check" ios/Runner/Info.plist
grep -A1 -E 'CFBundleIdentifier|CADisableMinimumFrameDurationOnPhone' ios/Runner/Info.plist || true
grep -m1 PRODUCT_BUNDLE_IDENTIFIER ios/Runner.xcodeproj/project.pbxproj
flutter build ios --release --no-codesign

APP=build/ios/iphoneos/Runner.app
# (ad hoc: every framework, then the application around them)
for f in "$APP"/Frameworks/*.framework "$APP"/Frameworks/*.dylib; do
	[ -e "$f" ] || continue
	codesign --force --sign - --timestamp=none "$f"
done
codesign --force --sign - --timestamp=none "$APP"
codesign -dv "$APP" 2>&1 | head -5
rm -rf "$OUT/Payload" "$OUT/FlutterCheck.ipa"
mkdir -p "$OUT/Payload"
cp -R "$APP" "$OUT/Payload/"
(cd "$OUT" && zip -qry FlutterCheck.ipa Payload && rm -rf Payload)
ls -l "$OUT/FlutterCheck.ipa"
