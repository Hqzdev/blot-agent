#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
output="${1:-.build/native}"
mkdir -p "$output/Guest"
# Этот бинарник помещается в гостевую macOS. На основном Mac он не запускается.
swiftc -O -o "$output/Guest/BlotGuestRunner" native/GuestRunner/main.swift
scripts/sign-native.sh --identifier com.blot.guest-runner "$output/Guest/BlotGuestRunner"
cp native/GuestRunner/install-guest.sh "$output/Guest/install-guest.sh"

# Foundation adapter загружается внутри sandbox Java и разрешает переданный bookmark.
mkdir -p "$output/native"
task_jdk="${JAVA_HOME:-$PWD/.build/tools/jdk-25.0.4.1+1/Contents/Home}"
xcrun clang -dynamiclib -fobjc-arc -framework Foundation -I "$task_jdk/include" -I "$task_jdk/include/darwin"     native/ProjectAccess/ProjectAccess.m -o "$output/native/libBlotProjectAccess.dylib"
scripts/sign-native.sh "$output/native/libBlotProjectAccess.dylib"
