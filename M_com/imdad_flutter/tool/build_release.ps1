<#
.SYNOPSIS
  بناء نسخ التوزيع (ويندوز + أندرويد) بعد فحص ما قبل الإصدار.

.DESCRIPTION
  1) يشغّل `dart run tool/check_release.dart` — إن فشل يتوقف السكربت ولا يبني شيئًا.
  2) `flutter build windows --release`
  3) `flutter build apk --release`

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
Invoke-Step 'بناء ويندوز' { flutter build windows --release }
Invoke-Step 'بناء أندرويد (APK)' { flutter build apk --release }

Write-Host "`n✔ اكتمل البناء" -ForegroundColor Green
Write-Host '  ويندوز : build\windows\x64\runner\Release\'
Write-Host '  أندرويد: build\app\outputs\flutter-apk\app-release.apk'
