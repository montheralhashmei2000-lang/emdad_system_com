"""
ui.print_helper — واجهة الطباعة داخل حزمة ui.

الطباعة الحقيقية مُنفَّذة في print_helper.py على جذر المشروع.
هذا الملف إعادة توجيه (shim) حتى لا تتكرر الشيفرة، ويحافظ على
التوقيعات التي تستدعيها الشاشات داخل الحزمة:

    from ..print_helper import print_inventory_count_form
    from ui.print_helper import print_daily_strength
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

# جذر المشروع هو المجلد الأب لمجلد ui.
# عند البناء بـ PyInstaller تكون الملفات في sys._MEIPASS لا بجوار الحزمة،
# فنبحث في الاثنين.
_PROJECT_ROOT = Path(__file__).resolve().parent.parent


def _bundle_root() -> Path:
    """مسار جذر المشروع سواء كان من مصادر أو من حزمة مبنية."""
    if getattr(sys, "frozen", False):
        meipass = getattr(sys, "_MEIPASS", None)
        if meipass:
            return Path(meipass)
    return _PROJECT_ROOT


_BUNDLE_ROOT = _bundle_root()
_REAL_MODULE_PATH = _BUNDLE_ROOT / "print_helper.py"

if str(_BUNDLE_ROOT) not in sys.path:
    sys.path.insert(0, str(_BUNDLE_ROOT))


def _load_real_module():
    """تحميل وحدة الطباعة الأصلية مرة واحدة فقط."""
    cached = sys.modules.get("print_helper")

    if cached is not None and getattr(cached, "__file__", None) == str(_REAL_MODULE_PATH):
        return cached

    spec = importlib.util.spec_from_file_location("print_helper", _REAL_MODULE_PATH)

    if spec is None or spec.loader is None:
        raise ImportError(f"تعذر تحميل وحدة الطباعة من: {_REAL_MODULE_PATH}")

    module = importlib.util.module_from_spec(spec)
    sys.modules["print_helper"] = module
    spec.loader.exec_module(module)
    return module


_real = _load_real_module()

# الدوال العامة التي تستخدمها الشاشات
print_inventory_report = _real.print_inventory_report
print_issue_voucher = _real.print_issue_voucher
print_issue_with_receipt = _real.print_issue_with_receipt
print_receipt_voucher = _real.print_receipt_voucher
print_receive_voucher = _real.print_receive_voucher
print_transfer_order = _real.print_transfer_order
print_transfer_with_receipt = _real.print_transfer_with_receipt
print_item_card = _real.print_item_card
print_returns_voucher = _real.print_returns_voucher
print_aggregated_report = _real.print_aggregated_report
print_daily_strength = _real.print_daily_strength
print_daily_workflow_report = _real.print_daily_workflow_report
print_inventory_count_form = _real.print_inventory_count_form
print_inventory_count_variances = _real.print_inventory_count_variances
print_aggregated_transfers_report = _real.print_aggregated_transfers_report

# أدوات مساعدة تُستخدم داخليًا，也可能 في اختبارات
_get_settings = _real._get_settings
_get_org_html = _real._get_org_html
_get_current_username = _real._get_current_username
_document_header = _real._document_header
_info_row_2cols = _real._info_row_2cols
_info_row_full = _real._info_row_full
_section_header = _real._section_header
_items_table = _real._items_table
_signatures = _real._signatures
_wrap = _real._wrap
_build_pages = _real._build_pages
_join_pages = _real._join_pages
_print_html = _real._print_html

__all__ = [name for name in dir() if name.startswith("print_")]
