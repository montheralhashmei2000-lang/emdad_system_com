"""
ui.views.transfer_view — شاشة تحويل المخزون.

التنفيذ الحقيقي في views/transfer_view.py على جذر المشروع، وهذا الملف
إعادة توجيه (shim) حتى تظهر الشاشة بكل وظائفها بدل جسم فارغ.
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent


def _bundle_root() -> Path:
    """مسار جذر المشروع سواء كان من مصادر أو من حزمة PyInstaller مبنية."""
    if getattr(sys, "frozen", False):
        meipass = getattr(sys, "_MEIPASS", None)
        if meipass:
            return Path(meipass)
    return _PROJECT_ROOT


_BUNDLE_ROOT = _bundle_root()
_REAL_MODULE_PATH = _BUNDLE_ROOT / "views" / "transfer_view.py"

if str(_BUNDLE_ROOT) not in sys.path:
    sys.path.insert(0, str(_BUNDLE_ROOT))


def _load_real_module():
    cached = sys.modules.get("_real_transfer_view")

    if cached is not None:
        return cached

    spec = importlib.util.spec_from_file_location("_real_transfer_view", _REAL_MODULE_PATH)

    if spec is None or spec.loader is None:
        raise ImportError(f"تعذر تحميل شاشة التحويل من: {_REAL_MODULE_PATH}")

    module = importlib.util.module_from_spec(spec)
    sys.modules["_real_transfer_view"] = module
    spec.loader.exec_module(module)
    return module


_real = _load_real_module()

TransferView = _real.TransferView

__all__ = ["TransferView"]