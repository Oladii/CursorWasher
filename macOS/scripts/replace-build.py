#!/usr/bin/env python3
"""Publish a verified bundle with macOS's atomic directory exchange."""
import ctypes
import os
from pathlib import Path
import sys

source, destination = map(Path, sys.argv[1:])
if not source.is_dir() or source.is_symlink() or destination.is_symlink():
    raise SystemExit("Expected application directories, not symlinks.")
if destination.exists():
    if not destination.is_dir():
        raise SystemExit("The build destination is not a directory.")
    libc = ctypes.CDLL(None, use_errno=True)
    rename = libc.renameatx_np
    rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    # AT_FDCWD, RENAME_SWAP: failure leaves both bundles in their original places.
    if rename(-2, os.fsencode(source), -2, os.fsencode(destination), 0x2) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))
else:
    os.rename(source, destination)
