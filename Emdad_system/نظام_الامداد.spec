# -*- mode: python ; coding: utf-8 -*-
"""
نظام الإمداد والتموين - PyInstaller Spec
Logistics & Supply Management - Build Spec
"""
from PyInstaller.utils.hooks import collect_data_files, collect_submodules

block_cipher = None

# Collect data files for SQLAlchemy, Babel, etc.
datas = []
hiddenimports = []

# UI assets
datas += collect_data_files('ui', includes=['*.qss', '*.png', '*.svg', '*.ico'])

# Babel locale data
try:
    datas += collect_data_files('babel')
except Exception:
    pass

# ملفات تُحمَّل وقت التشغيل عبر المسار (Path(__file__)) داخل حزمة ui،
# ويجب أن تكون موجودة بجوار التطبيق بعد البناء.
#   print_helper.py            -> ui/print_helper.py (شيم الطباعة)
#   views/transfer_view.py     -> ui/views/transfer_view.py (شيم التحويل)
# إضافةً إلى theme.py و api_service.py اللذين تستوردهما شاشات الجذر.
_RUNTIME_FILES = [
    ('print_helper.py', '.'),
    ('theme.py', '.'),
    ('api_service.py', '.'),
    ('views/transfer_view.py', 'views'),
]

for _src, _dst in _RUNTIME_FILES:
    import os as _os

    if _os.path.exists(_src):
        datas.append((_src, _dst))
    else:
        print(f'[spec] تحذير: ملف وقت التشغيل مفقود: {_src}')

# Hidden imports for dynamic modules
for mod in ['ui.views', 'ui.widgets', 'ui.screens',
            'core.models', 'core.services', 'core.security',
            'data.repositories_impl', 'sync']:
    try:
        hiddenimports += collect_submodules(mod)
    except Exception:
        pass

# Specific hidden imports
hiddenimports += [
    'sqlalchemy.dialects.sqlite',
    'sqlalchemy.orm.session',
    'PyQt6.QtCore',
    'PyQt6.QtGui',
    'PyQt6.QtWidgets',
    'qtawesome',
    'pyqtgraph',
    'httpx',
    'PIL',
]

# qtawesome و pyqtgraph يعتمدان على ملفات خطوط/بيانات وقت التشغيل
for _pkg in ('qtawesome', 'pyqtgraph'):
    try:
        datas += collect_data_files(_pkg)
    except Exception:
        print(f'[spec] تحذير: تعذر جمع بيانات {_pkg}')

a = Analysis(
    ['main.py'],
    pathex=['.'],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='نظام_الامداد',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='نظام_الامداد',
)