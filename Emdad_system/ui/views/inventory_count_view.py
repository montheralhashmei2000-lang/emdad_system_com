"""Inventory Count View - إدارة جرد المخزون (5 تبويبات)."""
from __future__ import annotations
from PyQt6.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QLabel,
    QComboBox, QDateEdit, QLineEdit, QPushButton, QTableWidget,
    QTableWidgetItem, QHeaderView, QMessageBox, QFrame, QGridLayout,
    QTabWidget, QTextEdit, QAbstractItemView, QGroupBox, QFormLayout,
    QFileDialog)
from PyQt6.QtCore import Qt, QDate
from PyQt6.QtGui import QColor, QDesktopServices
from ui.api_service import ApiService
from ui.theme import make_header_label, COLORS
from ..print_helper import print_inventory_count_form, print_inventory_count_variances


def _api(api, fn, *args, **kwargs):
    """Normalize backend responses: they return (success, data)."""
    try:
        return fn(*args, **kwargs)
    except Exception:
        return False, {}


class InventoryCountView(QWidget):
    """/screen جرد المخزون - خمسة تبويبات: إنشاء، قائمة، أصناف، مرفقات، تقارير."""

    def _init_ui(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(16, 16, 16, 16)
        root.setSpacing(14)
        root.addWidget(make_header_label("📦 جرد المخزون"))

        self.tabs = QTabWidget()
        self.tabs.setStyleSheet(_tab_style())
        root.addWidget(self.tabs)

        self._tab_create = QWidget()
        self._tab_list = QWidget()
        self._tab_items = QWidget()
        self._tab_attachments = QWidget()
        self._tab_reports = QWidget()

        self.tabs.addTab(self._tab_create, "➕ إنشاء جرد جديد")
        self.tabs.addTab(self._tab_list, "📋 قائمة الجرد")
        self.tabs.addTab(self._tab_items, "📦 أصناف الجرد")
        self.tabs.addTab(self._tab_attachments, "🗂️ المرفقات")
        self.tabs.addTab(self._tab_reports, "📊 التقارير")

        self._build_create_tab()
        self._build_list_tab()
        self._build_items_tab()
        self._build_attachments_tab()
        self._build_reports_tab()
        self._tab_list_current()

    def _card(self):
        f = QFrame()
        f.setStyleSheet(f"QFrame{{background:{COLORS['bg_card']};border:1px solid {COLORS['border']};border-radius:10px;padding:12px;}}")
        return f

    @staticmethod
    def _line_style():
        return (f"QLineEdit{{background:white;border:1px solid {COLORS['border']};"
                f"border-radius:6px;padding:6px 10px;color:{COLORS['text']};}}"
                f"QLineEdit:hover{{border-color:{COLORS['PRIMARY']};}}"
                f"QLineEdit:focus{{border-color:{COLORS['PRIMARY']};background:#f0fff4;}}")

    @staticmethod
    def _combo_style():
        return (f"QComboBox{{background:white;border:1px solid {COLORS['border']};"
                f"border-radius:6px;padding:6px 10px;color:{COLORS['text']};}}"
                f"QComboBox:hover{{border-color:{COLORS['PRIMARY']};}}"
                f"QComboBox::drop-down{{border:none;}}")

    # ----------------------------------------------------------- ATTACHMENT
    def _build_attachments_tab(self):
        lay = QVBoxLayout(self._tab_attachments)
        lay.setSpacing(12)
        card = self._card()
        cl = QGridLayout(card); cl.setHorizontalSpacing(14)
        lbl = QLabel("📎 مرفقات الجرد #:"); lbl.setStyleSheet("font-weight:bold;")
        self.lbl_attach_count = QLabel("لم يُحدَّد جرد")
        self.btn_upload = self._btn("⬆️ رفع مرفق", "#6366F1")
        self.btn_upload.clicked.connect(self._upload_attachment)
        cl.addWidget(lbl, 0, 0); cl.addWidget(self.lbl_attach_count, 0, 1)
        cl.addWidget(self.btn_upload, 0, 2)
        lay.addWidget(card)
        self.tbl_attach = QTableWidget()
        self.tbl_attach.setAlternatingRowColors(True)
        self.tbl_attach.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.tbl_attach.setColumnCount(4)
        self.tbl_attach.setHorizontalHeaderLabels(["#", "المرفق", "التاريخ", "الإجراء"])
        lay.addWidget(self.tbl_attach, 1)

    # ---------------------------------------------------------------- REPORTS
    def _build_reports_tab(self):
        lay = QVBoxLayout(self._tab_reports)
        lay.setSpacing(14)
        card = self._card()
        gl = QGridLayout(card); gl.setHorizontalSpacing(18)
        r = 0
        lbl1 = QLabel("🏭 المستودع:"); lbl1.setStyleSheet("font-weight:bold;")
        self.cb_wh_report = QComboBox(); self.cb_wh_report.setStyleSheet(self._combo_style())
        self.cb_wh_report.addItem("— اختر المستودع —", "")
        gl.addWidget(lbl1, r, 0); gl.addWidget(self.cb_wh_report, r, 1); r += 1
        lbl2 = QLabel("📋 رقم أمر الجرد:"); lbl2.setStyleSheet("font-weight:bold;")
        self.le_count_no = QLineEdit(); self.le_count_no.setPlaceholderText("أو اضغط لاختيار جرد")
        self.le_count_no.setStyleSheet(self._line_style())
        gl.addWidget(lbl2, r, 0); gl.addWidget(self.le_count_no, r, 1); r += 1
        lay.addWidget(card)

        row = QHBoxLayout()
        self.btn_form = self._btn("🖨️ اطبع استمارة الجرد", "#2563EB")
        self.btn_variance = self._btn("📊 اطبع فروقات الجرد", "#DC2626")
        self.btn_form.clicked.connect(self._print_form)
        self.btn_variance.clicked.connect(self._print_variance)
        row.addWidget(self.btn_form)
        row.addWidget(self.btn_variance)
        row.addStretch()
        lay.addLayout(row)
        self.lbl_report_status = QLabel()
        self.lbl_report_status.setStyleSheet(f"color:{COLORS['text']};font-size:13px;")
        lay.addWidget(self.lbl_report_status)
        lay.addStretch()
