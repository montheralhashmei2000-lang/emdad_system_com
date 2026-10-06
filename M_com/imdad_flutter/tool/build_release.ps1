<#
.SYNOPSIS
  بناء نسخ التوزيع (ويندوز + أندرويد) بعد فحص ما قبل الإصدار.

.DESCRIPTION
  1) يشغّل `dart run tool/check_release.dart` — إن فشل يتوقف السكربت ولا يبني شيئًا.
  2) `flutter build windows --release`
  3) `flutter build apk --release`

  الإصداران يُبنيان بتعتيم أسماء Dart (`--obfuscate`) وتُحفظ رموز فكّ التعتيم في
  `build\symbols\<الإصدار>\`. **احتفظ بهذا المجلد لكل إصدار يُوزَّع**: بدونه لا تُقرأ
  تتبعات الأخطاء القادمة من الميدان. لفكّ تتبّع:
  `flutter symbolize -i trace.txt -d build\symbols\<الإصدار>\app.android-arm64.symbols`

  شغّله من أي مكان: ينتقل إلى جذر المشروع تلقائيًا.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\build_release.ps1
#>
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

function Invoke-Step([string]$Title, [scriptblock]$Cmd) {
  Write-Host "`n== $Title ==" -ForegroundColor Cyan
  & $Cmd
  if ($LASTEXITCODE -ne 0) {
    Write-Host "✖ فشلت الخطوة: $Title (الرمز $LASTEXITCODE)" -ForegroundColor Red
    exit $LASTEXITCODE
  }
}

Invoke-Step 'فحص ما قبل الإصدار' { dart run tool/check_release.dart }

# رموز التعتيم مفصولة لكل إصدار (الرقم من pubspec.yaml) حتى لا يمحو إصدارٌ رموزَ سابقه.
$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value) -replace '\+', '-'
$symbols = "build\symbols\$version"
Write-Host "رموز فكّ التعتيم: $symbols" -ForegroundColor DarkGray

Invoke-Step 'بناء ويندوز' { flutter build windows --release --obfuscate "--split-debug-info=$symbols\windows" }
Invoke-Step 'بناء أندرويد (APK)' { flutter build apk --release --obfuscate "--split-debug-info=$symbols\android" }

Write-Host "`n✔ اكتمل البناء" -ForegroundColor Green
Write-Host '  ويندوز : build\windows\x64\runner\Release\'
Write-Host '  أندرويد: build\app\outputs\flutter-apk\app-release.apk'
Write-Host "  رموز التعتيم (احفظها مع الإصدار): $symbols"
