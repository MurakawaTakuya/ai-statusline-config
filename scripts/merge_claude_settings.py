#!/usr/bin/env python3

from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import tempfile


MANAGED_KEYS = ("statusLine", "subagentStatusLine")


def load_object(path: Path) -> dict:
    if not path.exists() or not path.read_text(encoding="utf-8").strip():
        return {}

    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o600

    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f".{path.name}.",
        delete=False,
    ) as handle:
        handle.write(content)
        temporary_path = Path(handle.name)

    os.chmod(temporary_path, mode)
    os.replace(temporary_path, path)


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "Usage: merge_claude_settings.py SETTINGS_JSON SETTINGS_SNIPPET_JSON",
            file=sys.stderr,
        )
        return 2

    target_path = Path(sys.argv[1]).expanduser()
    snippet_path = Path(sys.argv[2]).expanduser()
    settings = load_object(target_path)
    snippet = load_object(snippet_path)

    missing = [key for key in MANAGED_KEYS if key not in snippet]
    if missing:
        raise ValueError(f"Missing managed keys in snippet: {', '.join(missing)}")

    for key in MANAGED_KEYS:
        settings[key] = snippet[key]

    content = json.dumps(settings, ensure_ascii=False, indent=2) + "\n"
    atomic_write(target_path, content)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
