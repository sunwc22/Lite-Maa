import ctypes
import json
import os
import sys
import time
from pathlib import Path

from PIL import Image


def find_ipc_dll(mumu_root):
    root = Path(mumu_root)
    candidates = [
        root / "nx_device" / "12.0" / "shell" / "sdk" / "external_renderer_ipc.dll",
        root / "nx_main" / "sdk" / "external_renderer_ipc.dll",
        root / "shell" / "sdk" / "external_renderer_ipc.dll",
    ]
    for path in candidates:
        if path.exists():
            return path
    return None


def load_library(root, dll_path):
    for path in (dll_path.parent, Path(root) / "nx_main"):
        if path.exists():
            try:
                os.add_dll_directory(str(path))
            except (AttributeError, OSError):
                pass
    return ctypes.WinDLL(str(dll_path))


def capture(mumu_root, index, package_name, output_path):
    start = time.perf_counter()
    dll_path = find_ipc_dll(mumu_root)
    if not dll_path:
        return {"ok": False, "error": "external_renderer_ipc.dll not found"}

    lib = load_library(mumu_root, dll_path)
    lib.nemu_connect.argtypes = [ctypes.c_wchar_p, ctypes.c_int]
    lib.nemu_connect.restype = ctypes.c_int
    lib.nemu_disconnect.argtypes = [ctypes.c_int]
    lib.nemu_disconnect.restype = None
    lib.nemu_get_display_id.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
    lib.nemu_get_display_id.restype = ctypes.c_int
    lib.nemu_capture_display.argtypes = [
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_int,
        ctypes.POINTER(ctypes.c_int),
        ctypes.POINTER(ctypes.c_int),
        ctypes.c_void_p,
    ]
    lib.nemu_capture_display.restype = ctypes.c_int

    handle = lib.nemu_connect(str(Path(mumu_root)), int(index))
    if handle == 0:
        return {"ok": False, "error": "nemu_connect failed"}

    try:
        display_id = lib.nemu_get_display_id(handle, package_name.encode("utf-8"), 0)
        if display_id < 0:
            display_id = 0

        width = ctypes.c_int(0)
        height = ctypes.c_int(0)
        ret = lib.nemu_capture_display(handle, display_id, 0, ctypes.byref(width), ctypes.byref(height), None)
        if ret != 0 or width.value <= 0 or height.value <= 0:
            return {"ok": False, "error": f"capture init failed: {ret}"}

        size = width.value * height.value * 4
        buffer = (ctypes.c_ubyte * size)()
        ret = lib.nemu_capture_display(
            handle,
            display_id,
            size,
            ctypes.byref(width),
            ctypes.byref(height),
            buffer,
        )
        if ret != 0:
            return {"ok": False, "error": f"capture failed: {ret}"}

        image = Image.frombytes("RGBA", (width.value, height.value), bytes(buffer))
        image = image.transpose(Image.Transpose.FLIP_TOP_BOTTOM).convert("RGB")
        image.save(output_path)
        elapsed_ms = int((time.perf_counter() - start) * 1000)
        return {
            "ok": True,
            "method": "mumu-extras",
            "path": str(output_path),
            "width": width.value,
            "height": height.value,
            "display_id": display_id,
            "cost_ms": elapsed_ms,
        }
    finally:
        lib.nemu_disconnect(handle)


def main():
    if len(sys.argv) != 5:
        print(json.dumps({"ok": False, "error": "usage: mumu_capture.py root index package output"}))
        return 2

    result = capture(sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4])
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
