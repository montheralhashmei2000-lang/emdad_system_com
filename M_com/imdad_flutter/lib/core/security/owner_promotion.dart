import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';
import '../../data/repos/audit_repo.dart';
import '../../data/repos/users_repo.dart';
import '../../domain/access_control.dart';

/// نتيجة محاولة الترقية التلقائية للمالك.
enum OwnerPromotionOutcome {
  /// يوجد مالكٌ فعلًا — لا شيء يُفعل.
  alreadyHasOwner,

  /// رُقّي المدير الوحيد المحلي إلى مالك.
  promoted,

  /// لا مدير على الجهاز.
  noAdmin,

  /// مدير واحد لكن حسابه ليس محليًا (`local-…`): وصل بالمزامنة أو من مصدرٍ آخر.
  notLocal,

  /// أكثر من مدير: لا ترقية تلقائية — يُحدِّد أحدهم المالك يدويًا.
  ambiguous,

  /// جهاز فرع: المالك يصله بالمزامنة من جهاز الإدارة ولا يُحدَّد هنا.
  skippedBranch,
}

class OwnerPromotionResult {
  const OwnerPromotionResult(this.outcome, {this.userId = '', this.adminCount = 0});

  final OwnerPromotionOutcome outcome;

  /// المُرقّى (عند [OwnerPromotionOutcome.promoted]).
  final String userId;

  final int adminCount;

  bool get promoted => outcome == OwnerPromotionOutcome.promoted;
}

/// ترقية المالك — حلّ «الدجاجة والبيضة»: الصلاحيات الخاصة (`sys.*`) للمالك
/// وحده، ولا مالك في قاعدةٍ لم تعرف هذا الدور بعد.
///
/// **القاعدة:** إن لم يوجد مالك، وكان في الجهاز **مدير واحد فقط** وحسابه محلي
/// (`local-…`) صار مالكًا تلقائيًا. أكثر من مدير ⇒ لا ترقية (أيُّهم؟)، ويُنبَّه
/// المديرون ليحدّد أحدهم المالك. مدير غير محلي ⇒ لا ترقية.
///
/// **جهاز الفرع لا يُرقّي:** قد يرى بعضَ الحسابات وحدها قبل اكتمال المزامنة،
/// فيظن مديرًا واحدًا هو الوحيد وهو ليس كذلك. المالك يصله من جهاز الإدارة.
///
/// تُسجَّل الترقية في سجل التدقيق بخطورة عالية، وتحدث مرةً واحدة بطبيعتها:
/// بعدها يوجد مالك فلا تُعاد.
class OwnerPromotion {
  const OwnerPromotion._();

  static const String localPrefix = 'local-';
  static const String autoPromotedAction = 'owner.auto_promoted';
  static const String assignedAction = 'owner.assigned';

  static Future<List<User>> _admins(AppDatabase db) =>
      (db.select(db.users)..where((t) => t.role.equals(UserRole.admin))).get();

  static Future<bool> _hasOwner(AppDatabase db) async =>
      (await (db.select(db.users)..where((t) => t.role.equals(UserRole.owner))).get()).isNotEmpty;

  /// يرقّي المدير الوحيد المحلي إلى مالك إن انطبقت الشروط. آمنةٌ على التكرار.
  static Future<OwnerPromotionResult> run(AppDatabase db, {bool isBranchDevice = false}) async {
    if (isBranchDevice) return const OwnerPromotionResult(OwnerPromotionOutcome.skippedBranch);
    if (await _hasOwner(db)) return const OwnerPromotionResult(OwnerPromotionOutcome.alreadyHasOwner);
    final admins = await _admins(db);
    if (admins.isEmpty) return const OwnerPromotionResult(OwnerPromotionOutcome.noAdmin);
    if (admins.length > 1) {
      return OwnerPromotionResult(OwnerPromotionOutcome.ambiguous, adminCount: admins.length);
    }
    final only = admins.single;
    if (!only.id.startsWith(localPrefix)) {
      return const OwnerPromotionResult(OwnerPromotionOutcome.notLocal, adminCount: 1);
    }
    await (db.update(db.users)..where((t) => t.id.equals(only.id) & t.role.equals(UserRole.admin))).write(
      UsersCompanion(role: const Value(UserRole.owner), updatedAt: Value(DateTime.now())),
    );
    // `updatedAt` تغيّر: يُجدَّد توقيع الدور إن كان مفتاح المالك على هذا الجهاز.
    await UsersRepo(db).resign(only.id);
    await AuditRepo(db).log(
      action: autoPromotedAction,
      entityType: 'مستخدم',
      summary: 'ترقية «${only.username}» إلى مالك النظام تلقائيًا (المدير المحلي الوحيد)',
      details: {'userId': only.id, 'username': only.username},
      risk: AuditRepo.riskHigh,
      actorEmail: 'system',
    );
    return OwnerPromotionResult(OwnerPromotionOutcome.promoted, userId: only.id, adminCount: 1);
  }

  /// هل ينبغي أن يُحدِّد أحدُ المديرين المالكَ يدويًا؟ (لا مالك وأكثر من مدير.)
  static Future<bool> needsSelection(AppDatabase db) async {
    if (await _hasOwner(db)) return false;
    return (await _admins(db)).length > 1;
  }

  /// المديرون الذين يصلحون مالكًا.
  static Future<List<User>> candidates(AppDatabase db) async =>
      await _hasOwner(db) ? const [] : await _admins(db);

  /// يعيّن [userId] مالكًا (حين لا مالك). يرفض إن وُجد مالك أو لم يكن الهدف مديرًا.
  /// التحقق من هوية المُنفِّذ (كلمة مروره، وأنه ليس جهاز فرع) مسؤولية المستدعي.
  static Future<bool> assign(AppDatabase db, {required String userId, required String actorEmail}) async {
    if (await _hasOwner(db)) return false;
    final target = await (db.select(db.users)..where((t) => t.id.equals(userId))).getSingleOrNull();
    if (target == null || target.role != UserRole.admin) return false;
    await (db.update(db.users)..where((t) => t.id.equals(userId) & t.role.equals(UserRole.admin))).write(
      UsersCompanion(role: const Value(UserRole.owner), updatedAt: Value(DateTime.now())),
    );
    await UsersRepo(db).resign(userId, actorEmail: actorEmail);
    await AuditRepo(db).log(
      action: assignedAction,
      entityType: 'مستخدم',
      summary: 'تحديد «${target.username}» مالكًا للنظام',
      details: {'userId': userId, 'username': target.username},
      risk: AuditRepo.riskHigh,
      actorEmail: actorEmail,
    );
    return true;
  }
}
