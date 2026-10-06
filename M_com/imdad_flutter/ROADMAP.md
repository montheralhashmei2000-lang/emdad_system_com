# ROADMAP — خارطة شاشات المشروع

مصدر القائمة: فحص `lib/features/` (آخر تحديث: 2026-10-04).
الوصف مأخوذ من عنوان الشاشة (`ImdPageTitle`) ومن تعليقات الملف.

## الأعداد الحقيقية

مقيسة بتاريخ 2026-10-07 على الشجرة الحالية (`Get-ChildItem libeatures -Recurse -Filter *.dart`):

`lib/features/` يضم **119 ملفًا**، منها **58 ملف `*_screen.dart`**، و60 ملفًا يحمل `ImdPageTitle`. والبقية (نحو 61 ملفًا) تبويبات ونماذج ونوافذ ومكوّنات مساندة (`doc_kit` و`fuel_print` و`roster_tables` …).

> **تنبيه:** الجداول التفصيلية لكل مجلد أدناه كُتبت حين كان العدد 87 ولم تُعَد مراجعتها ملفًا ملفًا؛ ينقصها نحو 32 ملفًا أُضيفت لاحقًا (مثل ما في `home` و`inventory` و`fuel` و`archive` و`auth`). الأعداد في الجدول التالي هي الصحيحة.

## الملخص حسب القسم

| القسم | المجلد | الملفات | منها `*_screen.dart` |
|---|---|---|---|
| المنزل والغلاف | `home` | 10 | 2 |
| المصادقة | `auth` | 6 | 1 |
| المخزون | `inventory` | 18 | 7 |
| الأصناف والبيانات الأساسية | `catalog` | 11 | 7 |
| التخطيط والتشغيل اليومي | `daily` | 5 | 5 |
| المحروقات | `fuel` | 17 | 13 |
| التقارير | `reports` | 5 | 5 |
| الرؤى والقيادة | `insights` | 4 | 4 |
| المالية والارتباطات (القوة البشرية، المالية، التسليح) | `linkages` | 16 | 2 |
| البرقيات | `cables` | 2 | 1 |
| الأرشيف | `archive` | 6 | 1 |
| المستندات | `documents` | 3 | 0 |
| الإعدادات | `settings` | 11 | 7 |
| الجرد | `stocktake` | 3 | 1 |
| التنبيهات | `alerts` | 1 | 1 |
| المزامنة | `sync` | 1 | 1 |
| **الإجمالي** | | **119** | **58** |

---

## home (5)

| الملف | الوظيفة |
|---|---|
| `home/home_shell.dart` | غلاف التطبيق: الشريط الجانبي/القضيب/الشريط السفلي، الشريط العلوي، التنقل والصلاحيات |
| `home/dashboard_screen.dart` | لوحة القيادة ومركز عمليات المدير (بطاقات KPI) |
| `home/space_chooser_screen.dart` | اختيار مساحة العمل (الإعاشة / المحروقات) |
| `home/notification_bell.dart` | جرس التنبيهات (مساند) |
| `home/supply_groups.dart` | تجميع أبواب قائمة الإمداد (مساند) |

## auth (2)

| الملف | الوظيفة |
|---|---|
| `auth/login_screen.dart` | تسجيل الدخول، وتنبيه ترقية كلمة المرور القصيرة (< 8 أحرف) لغير المدراء |
| `auth/change_password_dialog.dart` | نافذة تغيير كلمة مرور المستخدم لنفسه |

## inventory (9)

| الملف | الوظيفة |
|---|---|
| `inventory/receive_screen.dart` | استلام بضاعة: سند وارد ومسودات وسجل |
| `inventory/issue_screen.dart` | صرف بضاعة للوحدات المستفيدة |
| `inventory/transfer_screen.dart` | التحويل المخزني بين المستودعات |
| `inventory/returns_screen.dart` | المرتجعات |
| `inventory/opening_screen.dart` | الأرصدة الافتتاحية |
| `inventory/pending_screen.dart` | أوامر التوريد المعلقة |
| `inventory/ration_order_screen.dart` | طلبيات الإعاشة |
| `inventory/doc_kit.dart` | عدّة السندات المشتركة (مساند) |
| `inventory/issue_drafts_view.dart` | مسودات الصرف (مساند) |

## catalog (11)

| الملف | الوظيفة |
|---|---|
| `catalog/items_screen.dart` | إدارة الأصناف |
| `catalog/warehouses_screen.dart` | المستودعات |
| `catalog/suppliers_screen.dart` | الموردون |
| `catalog/units_screen.dart` | الوحدات المستفيدة |
| `catalog/kitchens_screen.dart` | المطابخ والأفران |
| `catalog/authorities_screen.dart` | جهات الاعتمادات |
| `catalog/assets_screen.dart` | الأصول الثابتة |
| `catalog/asset_barcode_sheet.dart` | ورقة باركود الأصل (نافذة) |
| `catalog/camp_link_field.dart` | حقل ربط المعسكر (مساند) |
| `catalog/cylinders_view.dart` | عرض الأسطوانات (مساند) |
| `catalog/warehouse_dashboard_view.dart` | لوحة المستودع (مساند) |

## daily (5)

| الملف | الوظيفة |
|---|---|
| `daily/daily_operations_screen.dart` | حاوية التخطيط والتشغيل اليومي |
| `daily/strength_screen.dart` | التفريدة اليومية |
| `daily/ratios_screen.dart` | ضبط الاستحقاقات والمقررات |
| `daily/meal_plan_screen.dart` | خطط الوجبات |
| `daily/kitchen_log_screen.dart` | سجل التشغيل والطهي اليومي |

## fuel (15)

| الملف | الوظيفة |
|---|---|
| `fuel/fuel_dashboard_screen.dart` | لوحة قسم المحروقات |
| `fuel/fuel_moves_screen.dart` | حركة المحروقات (وارد/صرف/تحويل) |
| `fuel/fuel_allocations_screen.dart` | تفريدة المحروقات |
| `fuel/fuel_ledger_screen.dart` | أرصدة المستودعات وكشف الحركة |
| `fuel/fuel_stocktake_screen.dart` | جرد المحروقات |
| `fuel/fuel_consumption_screen.dart` | تقرير الاستهلاك |
| `fuel/fuel_daily_report_screen.dart` | تقرير الحركة اليومية |
| `fuel/fuel_official_report_screen.dart` | التقارير الرسمية |
| `fuel/fuel_directories_screen.dart` | مستودعات ووحدات المحروقات |
| `fuel/fuel_vehicles_screen.dart` | سجل المركبات |
| `fuel/fuel_settings_screen.dart` | إعدادات المحروقات |
| `fuel/fuel_groups.dart` · `fuel_plan_row.dart` · `fuel_print.dart` · `fuel_report_docs.dart` | مساندة: التجميع وسطر الخطة والطباعة ومستندات التقارير |

## reports (5)

| الملف | الوظيفة |
|---|---|
| `reports/reports_center_screen.dart` | مركز التقارير |
| `reports/balances_screen.dart` | الأرصدة الحالية |
| `reports/camp_ledger_screen.dart` | سجل حساب المعسكر |
| `reports/camp_settlement_screen.dart` | تصفية الشهر |
| `reports/actual_entitlement_screen.dart` | حساب الاستحقاق الفعلي |

## insights (4)

| الملف | الوظيفة |
|---|---|
| `insights/executive_cmd_screen.dart` | مركز القيادة التنفيذية |
| `insights/activity_intel_screen.dart` | ذكاء النشاط والانحرافات |
| `insights/health_ops_screen.dart` | صحة النظام والعمليات |
| `insights/sensitive_ops_screen.dart` | التغييرات الحساسة والمراجعة |

## linkages — المالية والارتباطات (16)

ثلاث شاشات في القائمة: **القوة البشرية** و**المالية** و**التسليح** (`linkages_screen.dart` و`personnel_screen.dart` تجمعها)، والباقي تبويبات ونماذج تُفتح داخلها.

| الملف | الوظيفة |
|---|---|
| `linkages/personnel_screen.dart` | القوة البشرية للإمداد والتموين (ملفات الأفراد، الحالات، طباعة الكشف) |
| `linkages/linkages_screen.dart` | شاشتا «المالية» و«التسليح» وتبويب القوة البشرية |
| `linkages/link_person_sheets.dart` | نماذج الفرد: إضافة/تعديل، تغيير الحالة، العودة، الملف الشخصي |
| `linkages/roster_tables.dart` · `roster_picker.dart` | جداول كشف القوة البشرية القابلة للاختيار عند الطباعة (الكشف، جدول لكل حالة، ملخصات) |
| `linkages/link_armament.dart` | تبويب التسليح: السلاح، القرون ونوعها، الذخيرة المستلمة، التعديل والرد |
| `linkages/link_finances.dart` | تبويب المالية: العهد · الإخلاءات · عقود الشراء · مسير العهدة · استلام مبلغ مالي |
| `linkages/custody_form.dart` · `custody_detail.dart` | تسجيل العهدة وتفاصيلها (العقود المرتبطة وملخصها المالي) |
| `linkages/contract_editor.dart` | محرر عقد الشراء (أصناف نص حر، قيمة الصنف في الفاتورة) |
| `linkages/custody_sheet_editor.dart` | محرر مسير العهدة (سعودي/يمني، تنبيه الفواتير المكررة، استيراد Excel) |
| `linkages/clearance_form.dart` | نموذج الإخلاء (عهدة / عقد / حر) |
| `linkages/finance_statement.dart` | كشف حساب مالية لصاحب العهدة |
| `linkages/invoice_scan_ui.dart` | مسح الفواتير: كاميرا الهاتف أو ملف ممسوح، OCR محلي (Tesseract) |
| `linkages/money_receipts_tab.dart` | استلام مبلغ مالي: سندات تُطبع بنموذج الجهة، والمبلغ كتابةً تلقائي |
| `linkages/link_export.dart` | تصدير Excel المشترك (مساند) |

### النظام المالي — أربع مراحل في دورة العهدة

المراحل هي دورة حياة العهدة كما يبنيها النظام (قاعدة البيانات v24 وما بعدها):

| المرحلة | ما يحدث | أين |
|---|---|---|
| 1. العهدة | تسجيل عهدة **مستلمة** (عليّ) أو **مسلَّمة** (على غيري)، بعملة سعودية أو يمنية وآخر أجل للإخلاء، وتنبيه للمتأخر | تبويب العهد، `custody_form` |
| 2. الشراء | عقود شراء مرتبطة بالعهدة: أصناف، قيمة الفاتورة، محل، تاريخ؛ ومسح الفواتير ضوئيًّا | تبويب عقود الشراء، `contract_editor`، `invoice_scan_ui` |
| 3. المسير | مسير العهدة: ما صُرف وما رُدّ بالعملتين وسعر الصرف، وإجماليات ملوّنة وجملة المتبقي، وطباعة بصيغة ملف الأصل | تبويب مسير العهدة، `custody_sheet_editor` |
| 4. الإخلاء | إغلاق العهدة: مطابق / فائض / عجز؛ «مُعتمد» وحده يغلقها ويكتب قيد **رصيد المالية**؛ وإلغاؤه يعكسه بقيد مضاد؛ وكشف حساب كل صاحب عهدة | تبويب الإخلاءات، `clearance_form`، `finance_statement` |

وإلى جانبها **استلام مبلغ مالي**: سند استلام نقدي أو حوالة يُطبع سندًا واحدًا في الصفحة. القواعد الحسابية في `lib/domain/finance.dart` و`custody_sheet.dart`، والجداول في `lib/data/db/linkage_tables.dart`.

> لا يحدّد المستودع «أربع مراحل» بنصٍّ رسمي؛ هذا التقسيم مستخرَج من بنية الشاشات والجداول. عدّله إن كانت لديك تسمية مختلفة.

## cables — البرقيات (2)

| الملف | الوظيفة |
|---|---|
| `cables/cables_screen.dart` | البرقيات الرسمية: واردة وصادرة من المعسكرات وإليها، مرفق PDF اختياري ببصمة سلامة، تزامن بين الأجهزة |
| `cables/cable_form.dart` | نموذج البرقية (إدخال وطباعة بخط النظام) |

## archive · documents — الأرشيف والمستندات (3)

| الملف | الوظيفة |
|---|---|
| `archive/electronic_archive_screen.dart` | الأرشيف الإلكتروني: حفظ المستندات والملفات بتصنيف ووسوم ورقم سند وبصمة |
| `archive/archive_auto_settings.dart` | إعدادات الأرشفة التلقائية لكل عملية (سندات، تقارير، عقود، مسيرات، سندات استلام المبالغ…) — تُعرض في الإعدادات وفي نافذة الأرشيف |
| `documents/doc_log_view.dart` | سجل المستندات: عرض وإعادة طباعة وتعديل وإلغاء سندات الاستلام والصرف والتحويل والمرتجعات (مساند) |

## settings (7)

| الملف | الوظيفة |
|---|---|
| `settings/settings_screen.dart` | الإعدادات العامة (تضم الأقسام المدمجة) |
| `settings/users_screen.dart` | المستخدمون والصلاحيات |
| `settings/audit_screen.dart` | سجل النشاط والتدقيق |
| `settings/branding_screen.dart` | هوية التطبيق والشعار |
| `settings/forms_designer_screen.dart` | مصمم النماذج المطبوعة |
| `settings/device_activation_screen.dart` | تفعيل الأجهزة وإصدار الرموز |
| `settings/verify_sign_screen.dart` | التحقق من توقيع مستند |

## stocktake · alerts · sync (3)

| الملف | الوظيفة |
|---|---|
| `stocktake/stocktake_screen.dart` | إدارة الجرد المخزني |
| `alerts/stock_alerts_screen.dart` | تنبيهات المخزون |
| `sync/sync_screen.dart` | مزامنة الأجهزة على الشبكة المحلية |

---

## ملاحظات

- الشاشات الجديدة تُضاف إلى قائمة `test/mobile_layout_test.dart` (انظر `CLAUDE.md`).
- `widgets/item_picker_field.dart` الوارد في نسخة قديمة من هذا الملف لم يعد موجودًا في `lib/features/`.
