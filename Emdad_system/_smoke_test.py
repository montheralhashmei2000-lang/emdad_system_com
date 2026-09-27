"""
فحص دخان (smoke test) للتطبيق بلا واجهة رسومية.
يتجاوز شاشة الدخول ويبني النافذة الرئيسية ويثبّت الثيم وقاعدة البيانات،
ثم يغلق التطبيق بعد لحظات. يُستخدم للتحقق قبل البناء (PyInstaller).

    python _smoke_test.py
"""
from __future__ import annotations

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# dialects/typing قد تنهار على بعض إصدارات بايثون
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PyQt6.QtWidgets import QApplication, QDialog  # noqa: E402

import main as app_main  # noqa: E402
import ui.main_window as mw  # noqa: E402


class _StubLoginDialog:
    """شاشة دخول وهمية: تقبل دائمًا حتى نصل إلى بناء الواجهة."""

    def __init__(self, api_service, parent=None, is_lock_screen=False):
        self.user_data = {
            "id": 1,
            "username": "smoke",
            "full_name": "فحص دخان",
            "role": "مدير",
            "permissions": {},
            "offline_mode": False,
        }

    def exec(self):
        return QDialog.DialogCode.Accepted


def main() -> int:
    app_main.setup_logging()
    app_main.initialize_database()

    qt_app = QApplication(sys.argv)
    qt_app.setApplicationName("نظام الإمداد والتموين")

    from ui.theme import setup_theme

    setup_theme(qt_app)

    mw.LoginDialog = _StubLoginDialog

    window = mw.MainWindow()
    window.show()

    # إغلاق بعد ثوانٍ حتى نتحقق من أن حلقة الأحداث تعمل بلا انهيار
    from PyQt6.QtCore import QTimer

    QTimer.singleShot(5000, qt_app.quit)

    code = qt_app.exec()

    print("SMOKE OK: MainWindow built, stylesheet applied, event loop ran.")
    window.close()
    return code


if __name__ == "__main__":
    sys.exit(main())
