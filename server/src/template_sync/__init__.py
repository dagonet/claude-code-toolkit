"""template-sync-tools, shipped from claude-code-toolkit.

__version__ is read at import from the VERSION file shipped as package data —
NOT from the repo root, which is not beside the package in a non-editable
install — and there is deliberately NO fallback. A server that cannot state
its version must not answer template_load_manifest: a wrong server_version is
a machine-wide load outage at every consumer carrying a requires_server floor.
"""
from importlib import resources as _resources

VERSION_PATH = _resources.files(__name__) / "VERSION"

try:
    __version__ = VERSION_PATH.read_text(encoding="utf-8").splitlines()[0].strip()
except (FileNotFoundError, OSError) as exc:
    raise ImportError(
        f"template_sync cannot determine its version: {VERSION_PATH} is missing or "
        "unreadable. Refusing to start rather than report a wrong server_version."
    ) from exc

_parts = __version__.split(".")
if len(_parts) != 3 or not all(p.isdigit() for p in _parts):
    raise ImportError(
        f"template_sync VERSION is not bare X.Y.Z: {__version__!r}. "
        "parse_version at every consumer accepts exactly three dotted integers."
    )
