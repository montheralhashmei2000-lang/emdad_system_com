import '../../data/db/app_database.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/access_control.dart';

/// تنبيه المرحلة الانتقالية: بعد الترقية انتقلت النسخ الاحتياطي والتفعيل
/// والمزامنة إلى المالك. يُعرض **مرةً واحدة** لكل مديرٍ غير مالك على هذا الجهاز
/// ثم لا يتكرر (حالته محلية فقط ولا تُزامَن).
class SysTransitionNotice {
  SysTransitionNotice(this.db);

  final AppDatabase db;

  static const String key = 'sysNotice';

  static const String message =
      'النسخ الاحتياطي والتفعيل والمزامنة انتقلت للمالك. تواصل معه.';

  /// هل يُعرض التنبيه لـ[user] الآن؟ (مدير غير مالك لم يرَه من قبل.)
  Future<bool> shouldShow(User user) async {
    if (!UserRole.isAdmin(user.role) || UserRole.isOwner(user.role)) return false;
    final seen = await SettingsRepo(db).read(key);
    return seen[user.id] != true;
  }

  Future<void> markSeen(User user) async {
    final repo = SettingsRepo(db);
    final seen = await repo.read(key);
    seen[user.id] = true;
    await repo.write(key, seen);
  }
}
