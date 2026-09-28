"""برنامج لفحص أداء مراحل بدء التشغيل (بدون تشغيل واجهة المستخدم)"""
import cProfile
import pstats
import io
from main import setup_logging, initialize_database

def profile_startup():
    profiler = cProfile.Profile()
    profiler.enable()

    # المرحلة الأولى: إعداد التسجيل
    setup_logging()

    # المرحلة الثانية: تهيئة قاعدة البيانات
    initialize_database()

    profiler.disable()

    # تحليل النتائج
    stream = io.StringIO()
    stats = pstats.Stats(profiler, stream=stream).sort_stats(pstats.SortKey.TIME)
    stats.print_stats(20)  # عرض أسرع 20 دالة

    # حفظ التقرير إلى ملف
    report_path = "startup_profile_report.txt"
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(stream.getvalue())

    print(f"تم حفظ تقرير الفحص في: {report_path}")

if __name__ == "__main__":
    profile_startup()