"""DSH sandbox compatibility shim for MinerU.

Problem (measured on Windows + DSH sandbox, workspace-write/danger modes):
`os.mkdir(path, mode)` with an EXPLICIT mode argument creates a directory whose
DACL is not accessible to the sandboxed process, so `tempfile.mkdtemp()` /
`tempfile.TemporaryDirectory()` hand back a directory that nothing can write
into. MinerU uses TemporaryDirectory for its internal API output root, so parsing
fails with `PermissionError: [WinError 5]` on `<tmp>/mineru-api-client-*/output`.
Plain `os.mkdir(path)` (no mode) inherits the sandbox grant and works.

This module is injected by parse.ps1 via PYTHONPATH whenever it sits next to the
script, and applies to every Python process MinerU spawns.
"""

import os as _os

_real_mkdir = _os.mkdir


def _mkdir_no_mode(path, mode=0o777, *, dir_fd=None):
    if dir_fd is None:
        return _real_mkdir(path)
    return _real_mkdir(path, mode, dir_fd=dir_fd)


_os.mkdir = _mkdir_no_mode
