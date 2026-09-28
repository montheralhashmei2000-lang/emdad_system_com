"""Offscreen startup smoke test for the root desktop application."""
from __future__ import annotations

import os
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PyQt6.QtWidgets import QApplication, QDialog  # noqa: E402

import main_window as mw  # noqa: E402
from theme import apply_theme  # noqa: E402


class _ApiStub:
    def __getattr__(self, name):
        return lambda *args, **kwargs: (False, {})


class _StubLoginDialog:
    def __init__(self, *args, **kwargs):
        self.user_data = {
            "id": 1,
            "username": "smoke",
            "full_name": "فحص دخان",
            "role": "ADMIN",
            "permissions": {},
            "offline_mode": False,
        }

    def exec(self):
        return QDialog.DialogCode.Accepted


def main() -> int:
    app = QApplication(sys.argv)
    apply_theme(app)
    mw.LoginDialog = _StubLoginDialog
    window = mw.MainWindow(api_service=_ApiStub())
    window.show()
    app.processEvents()
    expected = {label for items in mw.SIDEBAR_GROUPS.values() for label, _ in items}
    assert expected.issubset(window.sidebar_buttons)
    print(f"SMOKE OK: root MainWindow started; {len(expected)} sidebar items found.")
    window.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
