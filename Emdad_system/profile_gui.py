"""فحص أداء إنشاء النافذة الرئيسية بوضع offscreen"""
import os
os.environ["QT_QPA_PLATFORM"] = "offscreen"

import sys
import cProfile
import pstats
import io

from PyQt6.QtWidgets import QApplication

def profile_gui():
    # إنشاء تطبيق Qt (إذا لم يُنشأ مسبقاً)
    app = QApplication.instance()
    if app is None:
        app = QApplication(sys.argv)

    profiler = cProfile.Profile()
    profiler.enable()

    # استيراد وإ создания النافذة الرئيسية
    from main_window import MainWindow
    window = MainWindow()
    # لا نحتاج إلى إظهار النافذة؛ يكفي إنشاؤها لتحميل المكونات

    profiler.disable()

    # تحليل النتائج
    stream = io.StringIO()
    stats = pstats.Stats(profiler, stream=stream).sort_stats(pstats.SortKey.TIME)
    stats.print_stats(30)  # طباعة أبرز 30 دالة

    report_path = "gui_profile_report.txt"
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(stream.getvalue())

    print(f"تم حفظ تقرير فحص الواجهة في: {report_path}")

if __name__ == "__main__":
    profile_gui()