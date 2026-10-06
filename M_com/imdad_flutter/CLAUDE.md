# CLAUDE.md - Project Constitution & AI Guidelines

> Last audited: 2026-10-06 against the working tree (v8.0.0+800, schema v25). Every number below was measured then; re-measure before quoting.

## 1. Project Overview
- **Name:** Supply Chain & Inventory Management System (نظام الإمداد والتموين). Native app, **offline-first**, Android (APK) + Windows (EXE). Web is NOT a target.
- **Language:** Arabic (RTL). All UI text Arabic; code comments English for complex logic.
- **Goal:** Premium-ERP look and speed (Onyx Pro class), dense on desktop, usable one-handed on mobile.
- **Size (measured):** 285 hand-written Dart files in `lib/` (~89k lines + 53k generated `app_database.g.dart`), 119 files in `features/` (69 `*Screen` classes), 55 Drift tables, `kSchemaVersion = 25` (`lib/data/db/app_database.dart:103`), 125 test files / 1293 passing + 1 skipped, `flutter analyze` clean.
- **Two sections only:** Supply (`AppSpace.supply`, "الإمداد والتموين" — supply and rations are ONE section) and Fuel (`AppSpace.fuel`). There is no separate "Tamween" section (`lib/domain/app_space.dart`).

## 2. Mandatory Workflow Rules
- **Build:** `*.g.dart` are NOT committed. After clone/pull or any change under `lib/data/db/` tables run `dart run build_runner build --delete-conflicting-outputs`. Without it nothing compiles.
- **Before finishing any change:** `flutter analyze` must be clean; run the affected test files (`flutter test test/<file>`). Full `flutter test` takes ~7 min; run it once at the end, never in parallel with analyze.
- **Never** edit `.github/workflows/ci.yml`, `*.g.dart`, or `OwnerKey.publicKey` unless explicitly asked. CI = analyze + test (Ubuntu), `build apk --release`, `build windows --release` (Flutter pinned 3.47.4).
- **Commits/push only when asked.** Confirm the exact target file path before editing. If a change breaks build/lints, revert it and try another approach. Refactor screens incrementally.
- New `Imd*` behavior that changes an existing widget must stay backward compatible. Improve an existing component before adding a parallel one.
- Schema change ⇒ bump `kSchemaVersion`, add an `if (from < N)` block in `onUpgrade` (`app_database.dart:396+`), add a migration test (see `test/migration_v25_test.dart`).

## 3. Architecture
Layers (dependency flows downward only): `core/` (security, theme, UI kit, print, export) → `data/` (db, repos, sync, migration, backup, ocr) → `domain/` (pure rules; no Flutter/DB) → `features/<area>/` (screens). `main.dart` wires `AppDatabase`, `AuthService`, `AutoSyncService`, `IdleLock`, `BackupScheduler`, `ImdTheme` via `provider` **as DI only**; screen state is `setState`. Do NOT add Riverpod/Bloc/GetX.
- **Data flow:** Screen → `*Repo(db)` (`lib/data/repos/`) → Drift (`AppDatabase`, SQLCipher, WAL) → SQLite triggers (qty guards, item delete guard). Stock balances: `MovementsRepo._balanceRows()` (SQL `SUM/GROUP BY`, `movements_repo.dart:204`) is the source of truth; `StockLedger` (`domain/stock_ledger.dart`) is the in-memory twin and must stay equivalent (`test/balances_sql_test.dart`). Inactive statuses: `DRAFT, ORDER, CANCELLED, REJECTED`.
- Screens should call repos, not Drift directly. Known violations: items/issue/receive/transfer/warehouses/dashboard/insights screens (see §8). Do not add new ones.
- Key files per area:
  - Auth/permissions: `core/security/{auth_service,perm,warehouse_scope}.dart`, `domain/{access_control,perm_catalog,menu_doors,section_block}.dart`.
  - Crypto/owner: `core/security/{pbkdf2,password_hash,owner_key,owner_signature,device_activation,esign,owner_promotion}.dart`, `data/db/db_cipher.dart`, `data/migration/backup_crypto.dart`.
  - DB: `data/db/{app_database,tables/*,linkage_tables,archive_tables,cable_tables,pre_migration_backup}.dart`.
  - Sync: `data/sync/{lan_sync,sync_crypto,sync_trust,sync_marks,auto_sync}.dart`, `data/migration/legacy_import.dart` (merge entry point `importJson`).
  - Stock: `data/repos/movements_repo.dart`, `domain/{stock_ledger,issue_rules,unit_carry}.dart`.
  - Shell: `features/home/home_shell.dart` + `shell/*` (sidebar, topbar, bottom nav, menu tree `_menu`).
  - UI kit: `core/ui/**` (tokens `imd_tokens.dart`, table `widgets/imd_table.dart`, fields `widgets/imd_fields.dart`, `imd_form.dart`, `imd_page_chrome.dart`).
  - Print/export: `core/print/*` (pdf), `core/export/excel_export.dart`, `data/migration/{excel_import,xlsx_reader}.dart`.

## 4. Security Invariants (do not weaken)
- Passwords: PBKDF2-HMAC-SHA256, 310,000 iterations (legacy 45,000 re-hashed on login); lockout 5 tries/3 min per lowercase username; session 12 h and cleared on exit; min length 8; idle lock (`IdleLock`).
- DB: SQLCipher, key in `flutter_secure_storage` (`imdad.db.key`). Backups: `IMDBK2` AES-256-GCM. LAN sync: ECDH + HMAC-signed requests + AES-GCM payload, ±5 min timestamp, nonce replay set; pairing code 8 chars/10 min.
- Owner key: public key is embedded in `OwnerKey.publicKey`; private key lives only on the master device. Release builds throw if it is empty (`main.dart:43`). Device activation tokens and privileged-user rows are ECDSA P-256 signed.
- **Section blocking (v25):** `users.section_blocked` (`supply`, `fuel`, `admin.settings|users|audit|sync|devices`); fail-closed (corrupt JSON ⇒ all blocked); checked on the ORIGINAL page id in `AccessControl.can`, `Perm.has`, `AuthService.can`, `home_shell._hasPerm`. Owner never blocked.
- **Sync guard:** `LegacyImporter._userRejection` rejects (audit `sync.role_rejected`, high) a synced user row that raises role to admin/owner or removes a block without a valid owner signature (`users.owner_sig` JSON `{"r","s"}`; digests in `OwnerSignature`, `updatedAt` in Unix SECONDS). Any code that changes a privileged user's row must call `UsersRepo.resign(id)` afterwards. Existing admin/owner rows are also protected: a synced change to salt/hash, `permissions`, `warehouseScope`, `active` or `approved` needs a valid owner signature `c` (`OwnerSignature.credsDigest`, signed by `UsersRepo.resign`, rejection kind `credentials`). After upgrading, the owner must run `UsersRepo.signPrivilegedUsers` once so existing admin rows carry `c`; until then their credential changes are rejected on other devices. Admin password changes made on a non-owner device do not propagate (by design).
- File restore (`importFile`) is trusted (`sys.backup`) and audited `backup.restore`. Pre-migration backup `imdad.sqlite.pre-v25-<ts>` kept 7 days.
- Audit: `AuditRepo`; risks `high/sensitive/critical` are never pruned (`protectedRisks`), normal TTL 730 days. The log is not hash-chained.
- Drafts must not hold sensitive data in `SharedPreferences` (plain file). The issue-screen recovery draft lives in the encrypted DB (`SettingsRepo.readIssueRecovery`, local-only key `issueRecovery`); the old prefs key is migrated and wiped on first restore.

## 5. UI/UX Rules (CRITICAL)
**Theme & tokens**
- Light/Dark/System. NEVER hardcode colors: use `context.imd.xxx` (`ImdColors`, `imd_tokens.dart`) or `Theme.of(context).colorScheme`. Emerald `#047857` light / `#10B981` dark; Fuel section uses its own palette (`ImdColors.fuelLight/fuelDark`, `AppTheme.fuelSection`). PDF code may use `PdfColors`; barcode/QR painters may use fixed black/white via `ImdFixedColors`. `test/design_rules_test.dart` enforces both color and fixed-width rules — keep it green.
- Font: bundled `IBMPlexSansArabic` (`ImdSizes.font`); user-selectable families live in `ImdFonts`. No `google_fonts`.
- Radius/padding/heights come from `ImdSizes`/`ImdDensity` getters (they follow Classic style and High-Density). Never hardcode a radius that should follow them. Cards radius `ImdSizes.radius` (12; 2 in classic).

**Breakpoints (actual, not aspirational)**
- `ImdBp.mobileMax = 900` (`imd_tokens.dart:507`): `mobile` ⇒ ≤900, `wide` ≥1200, `tiny` ≤420. Used by tables, KPIs, pages.
- The shell has its own thresholds (`_Shell`, `home_shell.dart:111`): handheld ≤900 (endDrawer + `_BottomNav`, single page), 900–1150 icon rail (68px), >1150 full sidebar (default 290, drag-resizable 220–420, persisted `imdad.sideWidth`). Do not add a fourth threshold.
- Never use fixed widths for layout. Use `ImdFit(width:)` (shrinks to available), `LayoutBuilder`, `Expanded/Flexible`. Known tolerated fixed widths: unit cell `SizedBox(width: 104)` in entry rows, 280 settings/report nav panes.

**Shell (desktop)**
- Pages open as MDI tabs (`ImdPageTabs`, max 8 per section), kept alive by `ImdPageHost` (Offstage+TickerMode+ExcludeFocus). Both sections stay mounted when switching (`_SpaceState`; `test/section_switch_test.dart`). A hidden page whose data changed is flagged stale (orange dot + `ImdStaleBanner`), never auto-reloaded. Screens are NOT pushed as routes; full-screen `Navigator.push` is reserved for editors/scanner (items barcode, contract/custody editors, device activation, `ImdScan`). Dialogs/sheets: `showImdModal`.
- Status bar (`ImdStatusBar`, desktop only): clock, sync state (from `AutoSyncService`), record count (`ImdRecordScope`), density + classic toggles. Topbar: burger (mobile), `ImdMenuBar` (desktop), section switcher, notification bell, avatar. Android back: closes drawer → goes home → confirm exit (`PopScope`). Windows close button is intercepted and confirmed.
- Shortcuts (desktop only, `ImdShortcuts.supported`): Ctrl+S save, Ctrl+P print, Ctrl+N new, F5 refresh, Enter confirms dialogs, Esc closes pickers only (no global Esc).

**How to build a new screen**
1. Add the page id to `_menu` (`shell/home_shell_menu.dart`), `_pageBody` switch (`home_shell.dart`), a permission in `PermCatalog`, and its section in `AppSpace.pages`. A page that is a sub-section of another (e.g. Settings sections) is wrapped in `ImdEmbedScope` and gets no sidebar item.
2. Layout: `ImdPage(children: [ImdPageTitle(...), ImdICard(...), ImdChipsRow(...), ImdTable(...)])`; entry/voucher screens use `ImdStickyPage` (sticky scanner/header + sticky footer with Save/Approve/Print). Page-header tabs/actions go through `ImdPageTitle.actions`.
3. Tables: read tables use `ImdTable` with `pageSize: 50` (house standard; 100 for light rows) and `values:` (raw cells) on large read tables to enable Find/filter/group/count. Only items, suppliers and balances do today — add it to movement/ledger tables you touch. `onRowTap/rowMenu/rowColor` receive the ORIGINAL row index. Item-entry tables (receive, issue, transfer, returns, opening, ration order, stocktake) MUST use `ImdEntryTable` (flush cells, row = `ImdSizes.compactField`). Dropdown + quick-add ⇒ `ImdInputGroup`. On mobile tables stay tables (natural width, horizontal scroll, `freezeFirst`); `cards: true` is opt-in for small tables (unused today).
4. Fields: `ImdFld`/`ImdField` (`required` adds red `*`; `errorText`), `ImdSelect` (large searchable dialog, never a small dropdown), `ImdDateField` (picker only, stores `YYYY-MM-DD`, range 2000–2100), numbers via `number: true`. Pre-save validation uses `ImdValidationBox`/`ImdCheck` lists.
5. Feedback: `showImdToast(context, '✔ …')` / `error: true` (SnackBar based). No `AlertDialog` for success; confirmations via `imdConfirm`. Loading: use `ImdShimmerKpis/ImdShimmerTable` for tables/dashboards (`imd_shimmer.dart`); the legacy `ImdLd('⏳ جارٍ التحميل…')` text loader is used in 93 places — migrate when touching a screen.
6. After every `await`, guard `context`/`setState` with `mounted`.
7. Exports: `ExcelExport.build/writeToFile` (strings; mark numeric columns); printing via `DocumentPdf`/`PrintDoc` + `showPrintPreview` (layout from `SettingsRepo.printLayout()`), thermal via `thermal_print.dart`.
8. Add the page id to `test/mobile_layout_test.dart` (sweeps 320/360/740-landscape/800 at 1.3 text scale; text scale clamped by `kImdMaxTextScale`).

**Density & style:** `ImdDensity` (high density; touch targets never shrink) and `ImdStyle` (classic flat: radius 2, Tahoma, `ImdColors.classicLight`) are static switches applied by `ImdDensity.rebuildAll`. `ImdBp.touch` (Android/iOS) ⇒ touch min 46, field 40.

## 6. Cross-Platform Rules
- Must build for Android and Windows. `Platform.isWindows/isAndroid` only when unavoidable (window manager, Mica, file paths, scanner/OCR; OCR via Tesseract is Android-only). Packages must support both.
- Android release: R8 on, signing guard in `build.gradle.kts` refuses debug key; `allowBackup=false`. Camera, biometric, multicast permissions declared.

## 7. Testing
- `test/` has widget, domain, security, sync, migration, print, and layout suites (1293 pass, 1 platform-conditional skip in `native_feel_test.dart`). Security-critical suites: `sync_role_guard_test`, `sync_security_test`, `section_block_test`, `db_cipher_test`, `backup_crypto_test`, `pbkdf2_test`, `device_activation_test`, `owner_promotion_test`.
- Any bug fix gets a regression test. Do not weaken `design_rules_test`/`mobile_layout_test` to pass.

## 8. Known Issues (verified 2026-10-06; fix, don't paper over)
1. (Fixed 2026-10-06) Sync credential guard, global error hooks (`ErrorLogger.installGlobalHandlers`, called in `main`), and encrypted issue draft. Owner salt/hash no longer leave the device by sync (`DataExporter.toMap(includeOwnerSecrets: false)`; file backups keep them). Residual: admin hashes still replicate because branch admins and fresh branch devices need them to log in — protected only by PBKDF2 310k and the `c` guard.
2. `ImdTable` builds every row of the page eagerly in a `Table` (no virtualization); the frozen first column builds the table twice. Safe only because screens page at 50/100; `pageSize: null` on big data is a perf trap (`imd_table.dart:1024-1113`).
5. (Fixed 2026-10-07) LAN sync: nonce cache is time-pruned (`NonceCache`, 11 min, 100k cap); `POST /import` requires the signed body digest header (`x-imdad-body`) and is verified BEFORE the body is read; other paths cap bodies at 1 MB (`LanSync.maxSmallBodyBytes`); 500 replies no longer echo `$e`. Devices on an older build cannot push to this one until updated (they get a clear 401 message). Pulls from older devices still work.
6. (Fixed 2026-10-07) `ImdSizes` padding comments and `ROADMAP.md` totals corrected. `ROADMAP.md` per-folder file tables still list only the original 87 files. `ImdTable.values` coverage is 3 screens, not "all large tables".
7. Layering: ~15 screens query Drift directly (`items_screen`, `dashboard_screen`, `issue_screen`, insights…). Sync failure state is explicit (`AutoSyncService.failed`, `SyncResult.failed`) — never infer it from Arabic status text.
8. 13 files >1000 lines (`legacy_import` 1518, `issue_screen` 1462, `fuel_moves_screen` 1325, `linkage_repo` 1310 …) — split when touching.
9. `ImdInputGroup` has one use (`receive_screen.dart:636`) but is the mandated component for dropdown + quick-add, so it stays. Fuel moves screen uses `ImdTable` rather than `ImdEntryTable`. (`showImdToast` now caps at 420 via responsive margin.)
10. (Fixed 2026-10-07) Unknown usernames now run a dummy PBKDF2 (`AuthService.dummyVerifications`). Lockout counters still exist per name regardless of account existence.

## 9. Version & Rating Indicators (honest, 2026-10-06)
v8.0.0+800 · schema 25 · analyze clean · 1293/1294 tests. Ratings /10: security 8, permissions 8, stock integrity 8.5, code quality 7, UI Windows 8, UI Android 7, tests 8.5, production readiness 7.5, overall 7.7.

## 10. كسر التوافق الخلفي (Breaking Changes)
- **v8 / 2026-10-07 — مزامنة LAN:** `POST /import` يشترط ترويسة `x-imdad-body` (SHA-256 hex لجسم الطلب، داخلة في التوقيع) ويتحقق من التوقيع **قبل** قراءة الجسم. جهاز بإصدار أقدم يدفع بياناته (`push`) إلى جهاز محدَّث يُرفض بـ 401 «جهاز بإصدار قديم — حدّث التطبيق». السحب (`GET /export`, `/info`) من الأجهزة القديمة وإليها يعمل كما كان؛ فقط **دفع** القديم نحو المحدَّث يتعطل حتى يُحدَّث. لا يوجد مسار احتياطي قديم عمدًا (كان سيُبطل الإصلاح)؛ إن لزم اجعله مؤقتًا بسقف وتاريخ انتهاء وتدقيق `sync.legacy_push`. ملاحظة نشر: حدّث جهاز الإدارة بعد الفروع أو مع آخر دفعة منها.
- **المسارات غير `/import`:** سقف الجسم 1 م.ب (`LanSync.maxSmallBodyBytes`) بدل 128 م.ب.
- **حارس الحسابات:** تغيير ملح/بصمة/صلاحيات/نطاق/تفعيل حساب مدير أو مالك قائم يتطلب توقيع المالك `c`. شغّل `UsersRepo.signPrivilegedUsers` مرة واحدة بعد الترقية؛ وتغيير كلمة مرور مدير على جهاز بلا مفتاح المالك لا ينتقل لبقية الأجهزة.
- **بصمة المالك** لا تُرسل بالمزامنة (تُرسل في النسخ الاحتياطي الملفي): فلا يدخل المالك بكلمة مروره على جهاز فرع جديد حتى يُنشأ له حساب هناك أو يُستعاد من نسخة.
- **مسودة الصرف** انتقلت من SharedPreferences إلى القاعدة المشفّرة (`issueRecovery`)؛ تُرحَّل القديمة تلقائيًا عند أول استعادة.
