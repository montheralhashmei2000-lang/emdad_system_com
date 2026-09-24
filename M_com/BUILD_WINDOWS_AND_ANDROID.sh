#!/usr/bin/env bash
# بناء نظام الإمداد: APK موقّع (Android) — ويندوز EXE عند توفر مشروع Electron
# الاستخدام: ./BUILD_WINDOWS_AND_ANDROID.sh [android|windows|all]   (الافتراضي: android)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
WEB="$ROOT/source_web_v720"
APP="$ROOT/android_app"
TARGET="${1:-android}"

die() { echo "✖ $*" >&2; exit 1; }

check_web() {
  echo "== فحص صحة ملفات JS"
  for f in "$WEB"/*.js; do node --check "$f" || die "خطأ صياغة في $f"; done
}

build_android() {
  [ -f "$APP/android/keystore.properties" ] || die "keystore.properties غير موجود — APK لن يكون موقّعًا"
  [ -n "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" ] || die "ANDROID_HOME غير مضبوط"

  echo "== تثبيت الحزم ومزامنة Capacitor"
  cd "$APP"
  [ -d node_modules ] || npm install
  npx cap sync android

  echo "== بناء APK Release"
  cd "$APP/android"
  if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; then ./gradlew.bat assembleRelease; else chmod +x gradlew; ./gradlew assembleRelease; fi

  APK="$APP/android/app/build/outputs/apk/release/app-release.apk"
  [ -f "$APK" ] || die "لم يُنتج APK"
  BT=$(ls -d "${ANDROID_HOME:-$ANDROID_SDK_ROOT}"/build-tools/* 2>/dev/null | sort -V | tail -1 || true)
  if [ -n "$BT" ]; then
    APKSIGNER="$BT/apksigner"; [ -f "$APKSIGNER.bat" ] && APKSIGNER="$APKSIGNER.bat"
    "$APKSIGNER" verify --verbose "$APK" | head -5
  fi
  mkdir -p "$ROOT/release"
  cp "$APK" "$ROOT/release/imdad-7.3.0.apk"
  echo "✔ APK: release/imdad-7.3.0.apk"
}

build_windows() {
  ELECTRON="$ROOT/electron_app"
  [ -f "$ELECTRON/package.json" ] || die "مشروع Electron غير موجود ($ELECTRON) — يلزم main.js و preload.js"
  cd "$ELECTRON"
  [ -d node_modules ] || npm install
  rm -rf web && cp -r "$WEB" web
  npx electron-builder --win portable
}

check_web
case "$TARGET" in
  android) build_android ;;
  windows) build_windows ;;
  all)     build_android; build_windows ;;
  *)       die "هدف غير معروف: $TARGET" ;;
esac
