"""Inventory Count View - إدارة جرد المخزون (5 تبويبات)."""
from __future__ import annotations
from PyQt6.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QLabel,
    QComboBox, QDateEdit, QLineEdit, QPushButton, QTableWidget,
    QTableWidgetItem, QHeaderView, QMessageBox, QFrame, QGridLayout,
    QTabWidget, QTextEdit, QAbstractItemView, QGroupBox, QFormLayout,
    QFileDialog)
from PyQt6.QtCore import Qt, QDate, QUrl as QtCoreQUrl
from PyQt6.QtGui import QColor, QDesktopServices
from ui.api_service import ApiService
from ui.theme import make_header_label, COLORS
from print_helper import print_inventory_count_form, print_inventory_count_variances


def _api(api, fn, *args, **kwargs):
    """Normalize backend responses: they return (success, data)."""
    try:
        return fn(*args, **kwargs)
    except Exception:
        return False, {}


class InventoryCountView(QWidget):
    """/screen جرد المخزون - خمسة تبويبات: إنشاء، قائمة، أصناف، مرفقات، تقارير."""

    def __init__(self, parent=None, api_service=None):
        super().__init__(parent)
        self.api = api_service or ApiService()
        self.setLayoutDirection(Qt.LayoutDirection.RightToLeft)
        self._init_ui()
        self._load_warehouses()
        self._load_items()
        self._load_counts()

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

    @staticmethod
    def _btn(text, color):
        btn = QPushButton(text)
        btn.setStyleSheet(f"""
            QPushButton {{
                background-color: {color};
                color: white;
                border: none;
                padding: 8px 16px;
                border-radius: 6px;
                font-weight: bold;
            }}
            QPushButton:hover {{
                background-color: {color}dd;
            }}
            QPushButton:pressed {{
                background-color: {color}bb;
            }}
        """)
        return btn

    @staticmethod
    def _tab_style():
        return """
            QTabWidget::pane {
                border: 1px solid #E5E7EB;
                border-radius: 8px;
                background: white;
                margin-top: -1px;
            }
            QTabBar::tab {
                background: #F3F4F6;
                color: #6B7280;
                border: 1px solid #E5E7EB;
                border-bottom: none;
                border-top-left-radius: 6px;
                border-top-right-radius: 6px;
                padding: 10px 16px;
                margin-right: 2px;
            }
            QTabBar::tab:selected {
                background: white;
                color: #10B981;
                border-color: #E5E7EB;
                border-bottom: 2px solid #10B981;
            }
            QTabBar::tab:!selected:hover {
                background: #E5E7EB;
            }
        """

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


