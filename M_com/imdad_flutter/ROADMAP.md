# ROADMAP — خارطة شاشات المشروع

مصدر القائمة: فحص `lib/features/` (ملفات `*_screen.dart` و`*_shell.dart` و`*_dialog.dart`).
الوصف مأخوذ من عنوان الشاشة (`ImdPageTitle`) واسم الملف.

## الملخص

| القسم | المجلد | العدد |
|---|---|---|
| المنزل والغلاف | `home` | 3 |
| المصادقة | `auth` | 1 |
| المخزون | `inventory` | 7 |
| الأصناف والبيانات الأساسية | `catalog` | 7 |
| التخطيط والتشغيل اليومي | `daily` | 5 |
| المحروقات | `fuel` | 11 |
| التقارير | `reports` | 5 |
| الرؤى والقيادة | `insights` | 4 |
| الإعدادات | `settings` | 7 |
| الجرد | `stocktake` | 1 |
| التنبيهات | `alerts` | 1 |
| المزامنة | `sync` | 1 |
| **الإجمالي** | | **53** |

53 = 52 ملف `*_screen.dart` + 1 ملف `*_shell.dart` (`home_shell.dart`). لا توجد ملفات `*_dialog.dart` في المشروع؛ النوافذ تُبنى عبر `showImdModal` في `lib/core/ui/imd_widgets.dart`.

## home (3)

| الملف | الوظيفة |
|---|---|
| `home/home_shell.dart` | غلاف التطبيق: الشريط الجانبي/القضيب/الشريط السفلي، الشريط العلوي، والتنقل بين الشاشات والصلاحيات |
| `home/dashboard_screen.dart` | لوحة القيادة ومركز عمليات المدير (بطاقات KPI) |
| `home/space_chooser_screen.dart` | اختيار مساحة العمل (الإعاشة / المحروقات) |

## auth (1)

| الملف | الوظيفة |
|---|---|
| `auth/login_screen.dart` | تسجيل دخول المستخدم |

## inventory (7)

| الملف | الوظيفة |
|---|---|
| `inventory/receive_screen.dart` | استلام بضاعة: سند وارد جديد ومسودات وسجل |
| `inventory/issue_screen.dart` | صرف بضاعة للوحدات المستفيدة |
| `inventory/transfer_screen.dart` | التحويل المخزني بين المستودعات |
| `inventory/returns_screen.dart` | المرتجعات |
| `inventory/opening_screen.dart` | الأرصدة الافتتاحية للأصناف |
| `inventory/pending_screen.dart` | أوامر التوريد المعلقة |
| `inventory/ration_order_screen.dart` | طلبيات الإعاشة |

## catalog (7)

| الملف | الوظيفة |
|---|---|
| `catalog/items_screen.dart` | إدارة الأصناف |
| `catalog/warehouses_screen.dart` | المستودعات |
| `catalog/suppliers_screen.dart` | الموردون |
| `catalog/units_screen.dart` | الوحدات المستفيدة |
| `catalog/kitchens_screen.dart` | المطابخ والأفران |
| `catalog/authorities_screen.dart` | جهات الاعتمادات |
| `catalog/assets_screen.dart` | الأصول الثابتة |

## daily (5)

| الملف | الوظيفة |
|---|---|
| `daily/daily_operations_screen.dart` | حاوية التخطيط والتشغيل اليومي (تجمع شاشات القسم) |
| `daily/strength_screen.dart` | التفريدة اليومية |
| `daily/ratios_screen.dart` | ضبط الاستحقاقات والمقررات (إدخال شبكي) |
| `daily/meal_plan_screen.dart` | خطط الوجبات |
| `daily/kitchen_log_screen.dart` | سجل التشغيل والطهي اليومي |

## fuel (11)

| الملف | الوظيفة |
|---|---|
| `fuel/fuel_dashboard_screen.dart` | لوحة قسم المحروقات |
| `fuel/fuel_moves_screen.dart` | حركة المحروقات (وارد/صرف/تحويل) |
| `fuel/fuel_allocations_screen.dart` | تفريدة المحروقات |
| `fuel/fuel_ledger_screen.dart` | أرصدة المستودعات وكشف الحركة والاستحقاق مقابل الصرف |
| `fuel/fuel_stocktake_screen.dart` | جرد المحروقات |
| `fuel/fuel_consumption_screen.dart` | تقرير الاستهلاك |
| `fuel/fuel_daily_report_screen.dart` | تقرير الحركة اليومية للمحروقات |
| `fuel/fuel_official_report_screen.dart` | التقارير الرسمية |
| `fuel/fuel_directories_screen.dart` | مستودعات ووحدات المحروقات |
| `fuel/fuel_vehicles_screen.dart` | سجل المركبات |
| `fuel/fuel_settings_screen.dart` | إعدادات المحروقات |

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
| `insights/health_ops_screen.dart` | مركز صحة النظام والعمليات |
| `insights/sensitive_ops_screen.dart` | التغييرات الحساسة والمراجعة |

## settings (7)

| الملف | الوظيفة |
|---|---|
| `settings/settings_screen.dart` | الإعدادات العامة |
| `settings/users_screen.dart` | مركز المستخدمين والصلاحيات |
| `settings/audit_screen.dart` | سجل النشاط والتدقيق |
| `settings/branding_screen.dart` | هوية التطبيق والشعار |
| `settings/forms_designer_screen.dart` | مصمم النماذج المطبوعة |
| `settings/device_activation_screen.dart` | تفعيل الأجهزة |
| `settings/verify_sign_screen.dart` | التحقق من توقيع مستند |

## stocktake (1) · alerts (1) · sync (1)

| الملف | الوظيفة |
|---|---|
| `stocktake/stocktake_screen.dart` | إدارة الجرد المخزني |
| `alerts/stock_alerts_screen.dart` | تنبيهات المخزون |
| `sync/sync_screen.dart` | مزامنة الأجهزة على الشبكة المحلية |

## ملفات مساندة (ليست شاشات)

`catalog/`: `asset_barcode_sheet`، `camp_link_field`، `cylinders_view`، `warehouse_dashboard_view` ·
`documents/doc_log_view` (سجل المستندات) ·
`fuel/`: `fuel_groups`، `fuel_plan_row`، `fuel_print`، `fuel_report_docs` ·
`home/`: `notification_bell`، `supply_groups` ·
`inventory/`: `doc_kit`، `issue_drafts_view` ·
`widgets/item_picker_field.dart` (مجلد `widgets` داخل `features`، خارج `lib/core/ui/`).
