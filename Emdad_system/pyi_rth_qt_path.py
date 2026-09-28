"""Prefer the Qt DLLs shipped with the frozen application."""
import os
import sys
import ctypes


if sys.platform == "win32":
    _qt_bin = os.path.join(sys._MEIPASS, "PyQt6", "Qt6", "bin")
    if os.path.isdir(_qt_bin):
        os.environ["PATH"] = _qt_bin + os.pathsep + os.environ.get("PATH", "")
        # Keep the Windows DLL search directory registered for the process.
        _qt_dll_directory = os.add_dll_directory(_qt_bin)
        # Pin this bundle's Qt libraries before importing the PyQt extensions.
        _dll_search_flags = 0x00000100 | 0x00001000
        for _dll_name in ("Qt6Core.dll", "Qt6Gui.dll", "Qt6Widgets.dll"):
            ctypes.WinDLL(
                os.path.join(_qt_bin, _dll_name),
                winmode=_dll_search_flags,
            )
