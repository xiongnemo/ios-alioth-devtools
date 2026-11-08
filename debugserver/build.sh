#!/bin/bash
# debugserver for iOS (arm64), built from LLVM's own source on macOS with Xcode. No CMake and no LLVM install: the
# program is three dozen files, compiled here one by one.
#   ./build.sh                     (LLVM_TAG=llvmorg-19.1.7 by default)
# OUT=DIR (default ../build/debugserver): DIR/debugserver, DIR/debugserver-<version>-ios-arm64.tar.gz
#
# This is LLVM's "debugserver-nonui": it attaches to a running process (--attach=<pid>, --waitfor=<name>) and launches
# plain programs, but it does not ask SpringBoard/FrontBoard to launch an app (that needs Apple's private headers).
#
# The public iPhoneOS SDK leaves out a few headers debugserver includes (mach/mach_vm.h is there but only says
# "#error unsupported"; sys/ptrace.h, libproc.h, sys/proc_info.h, bsm/audit_session.h and the MIG file
# mach/mach_exc.defs are missing). The functions behind them are in iOS's libSystem all the same, so the macOS SDK of
# this machine stands in for them while compiling; nothing of it is copied into this repository or into the result.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
LLVM_TAG=${LLVM_TAG:-llvmorg-19.1.7}
OUT=${OUT:-$HERE/../build/debugserver}
SRC=${SRC:-$OUT/llvm-project}
MIN=${MIN:-14.0}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
MAC_SDK=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk iphoneos --find clang)
CXX=$(xcrun --sdk iphoneos --find clang++)
MIG=$(xcrun --find mig)
echo "build.sh: $LLVM_TAG, iOS $MIN+, $IOS_SDK"

# 1. Source: only debugserver and the two lldb headers it borrows.
if [ ! -d "$SRC/.git" ]; then
	git init -q "$SRC"
	git -C "$SRC" remote add origin https://github.com/llvm/llvm-project.git
	git -C "$SRC" sparse-checkout set --no-cone /lldb/tools/debugserver/ /lldb/include/lldb/Host/ \
		/lldb/source/Host/common/SocketAddress.cpp /lldb/LICENSE.TXT
	git -C "$SRC" fetch -q --depth 1 origin tag "$LLVM_TAG"
	git -C "$SRC" checkout -q FETCH_HEAD
fi
D=$SRC/lldb/tools/debugserver/source
OBJ=$OUT/obj
INC=$OUT/include
rm -rf "$OBJ" "$INC"
mkdir -p "$OBJ" "$INC/mach"

# 2. The stand-ins: mach_vm.h ahead of the iPhoneOS SDK's, the missing ones after it (-idirafter is reached only for
# a header the iPhoneOS SDK does not have).
cp "$MAC_SDK/usr/include/mach/mach_vm.h" "$INC/mach/"

# 3. Mach exception interfaces, from mach_exc.defs.
(cd "$OBJ" && "$MIG" -arch arm64 -isysroot "$MAC_SDK" "$D/MacOSX/dbgnub-mig.defs")

# 4. The version string LLVM's CMake would configure.
V=${LLVM_TAG#llvmorg-}
IFS=. read -r MAJ MINR PAT <<< "$V"
cat > "$OBJ/debugserver_vers.c" <<EOF
const unsigned char debugserverVersionString[] __attribute__ ((used)) = "@(#)PROGRAM:LLDB  PROJECT:lldb-$MAJ.$MINR.$PAT" "\\n";
const double debugserverVersionNumber __attribute__ ((used)) = (double)$MAJ.$MINR;
EOF

FLAGS=(-target "arm64-apple-ios$MIN" -isysroot "$IOS_SDK" -isystem "$INC" -idirafter "$MAC_SDK/usr/include"
	-I"$D" -I"$D/MacOSX" -I"$D/MacOSX/arm64" -I"$OBJ" -I"$SRC/lldb/include" -I"$SRC/lldb/source"
	-DLLDB_USE_OS_LOG -O2 -g -fno-common -Wno-deprecated-declarations -Wno-unused-command-line-argument)
# (LLVM's list less libdebugserver.cpp: debugserver.cpp's main again, for embedding it in another program; CMake
# links the list as an archive, so that member is never pulled in)
SOURCES=(DNBArch.cpp DNBBreakpoint.cpp DNB.cpp DNBDataRef.cpp DNBError.cpp DNBLog.cpp DNBRegisterInfo.cpp
	DNBThreadResumeActions.cpp JSON.cpp StdStringExtractor.cpp StringConvert.cpp PseudoTerminal.cpp
	PThreadEvent.cpp PThreadMutex.cpp RNBContext.cpp RNBRemote.cpp RNBServices.cpp RNBSocket.cpp SysSignal.cpp
	TTYState.cpp debugserver.cpp
	MacOSX/CFBundle.cpp MacOSX/CFString.cpp MacOSX/Genealogy.cpp MacOSX/MachException.cpp MacOSX/MachProcess.mm
	MacOSX/MachTask.mm MacOSX/MachThread.cpp MacOSX/MachThreadList.cpp MacOSX/MachVMMemory.cpp
	MacOSX/MachVMRegion.cpp MacOSX/OsLogger.cpp MacOSX/arm64/DNBArchImplARM64.cpp)
objs=()
compile() { # source object
	case $1 in
	*.mm) "$CXX" "${FLAGS[@]}" -std=c++17 -stdlib=libc++ -x objective-c++ -c "$1" -o "$2" ;;
	*.cpp) "$CXX" "${FLAGS[@]}" -std=c++17 -stdlib=libc++ -c "$1" -o "$2" ;;
	*.c) "$CC" "${FLAGS[@]}" -c "$1" -o "$2" ;;
	esac
}
for s in "${SOURCES[@]}"; do
	o=$OBJ/$(echo "$s" | tr / _).o
	echo "  $s"
	compile "$D/$s" "$o"
	objs+=("$o")
done
for s in "$SRC/lldb/source/Host/common/SocketAddress.cpp" "$OBJ/mach_excServer.c" "$OBJ/mach_excUser.c" \
		"$OBJ/debugserver_vers.c"; do
	o=$OBJ/$(basename "$s").o
	echo "  $(basename "$s")"
	compile "$s" "$o"
	objs+=("$o")
done

# 5. Link, with the Info.plist LLVM embeds, and sign: ad hoc, with the entitlements next to this script.
"$CXX" -target "arm64-apple-ios$MIN" -isysroot "$IOS_SDK" -stdlib=libc++ -o "$OUT/debugserver" "${objs[@]}" \
	-framework Foundation -framework CoreFoundation -framework Security -lcompression \
	-Wl,-sectcreate,__TEXT,__info_plist,"$D/../resources/lldb-debugserver-Info.plist"
sed 's/\r$//' "$HERE/entitlements.plist" > "$OBJ/entitlements.plist"
codesign -f -s - --entitlements "$OBJ/entitlements.plist" "$OUT/debugserver"
file "$OUT/debugserver"
otool -L "$OUT/debugserver"
codesign -d --entitlements - "$OUT/debugserver" 2>/dev/null | head -60 || true

# 6. The package: the program, its entitlements, LLVM's licence.
PKG=$OUT/debugserver-$V-ios-arm64
rm -rf "$PKG" "$PKG.tar.gz"
mkdir -p "$PKG"
cp "$OUT/debugserver" "$OBJ/entitlements.plist" "$PKG/"
cp "$SRC/lldb/LICENSE.TXT" "$PKG/LICENSE.TXT"
cat > "$PKG/README.txt" <<EOF
debugserver from LLVM $V (lldb/tools/debugserver), built for iOS $MIN+ arm64 by
https://github.com/xiongnemo/ios-alioth-devtools. LLVM's licence: LICENSE.TXT (Apache-2.0 WITH LLVM-exception).
Signed ad hoc with entitlements.plist. It runs as root on an iOS that does not demand Apple's signature (the
Redmi K40 port), or wherever something re-signs it.
  debugserver 0.0.0.0:7777 --attach=<pid>      (or --waitfor=<process name>, or a program path and its arguments)
  lldb:  (lldb) process connect connect://<phone>:7777
EOF
tar -C "$OUT" -czf "$PKG.tar.gz" "$(basename "$PKG")"
ls -l "$PKG.tar.gz"
