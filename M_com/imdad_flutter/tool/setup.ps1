# تهيئة مشروع Flutter وتشغيل الفحوص بعد اكتمال تثبيت الـ SDK.
# الاستخدام:  powershell -ExecutionPolicy Bypass -File tool\setup.ps1
param(
  [string]$FlutterHome = "D:\flutter",
  [switch]$BuildApk
)

$ErrorActionPreference = "Stop"
$flutter = Join-Path $FlutterHome "bin\flutter.bat"
$dart = Join-Path $FlutterHome "bin\dart.bat"

if (-not (Test-Path $flutter)) {
  Write-Host "لم يُعثر على Flutter في $FlutterHome — فك ضغط الحزمة أولًا." -ForegroundColor Red
  exit 1
}

Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "== إنشاء منصات android/windows إن لم تكن موجودة =="
if (-not (Test-Path "android")) { & $flutter create --platforms=android,windows . }

Write-Host "== جلب الحزم =="
& $flutter pub get

Write-Host "== توليد كود Drift =="
& $dart run build_runner build --delete-conflicting-outputs

Write-Host "== التحليل الساكن =="
& $flutter analyze

Write-Host "== الاختبارات =="
& $flutter test

if ($BuildApk) {
  Write-Host "== بناء APK =="
  & $flutter build apk --release
}

Write-Host "تمت التهيئة." -ForegroundColor Green
