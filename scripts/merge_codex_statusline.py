#!/usr/bin/env python3

from __future__ import annotations

import os
from pathlib import Path
import re
import sys
import tempfile
import tomllib


MANAGED_KEYS = ("status_line", "status_line_use_colors")
TUI_HEADER = re.compile(r"(?m)^[ \t]*\[tui\][ \t]*(?:#.*)?(?:\r?\n|$)")
TABLE_HEADER = re.compile(r"(?m)^[ \t]*\[[^\n]+\][ \t]*(?:#.*)?(?:\r?\n|$)")
ASSIGNMENT = re.compile(r"^[ \t]*(status_line|status_line_use_colors)[ \t]*=")


def remove_managed_assignments(body: str) -> str:
    lines = body.splitlines(keepends=True)
    output: list[str] = []
    index = 0

    while index < len(lines):
        match = ASSIGNMENT.match(lines[index])
        if not match:
            output.append(lines[index])
            index += 1
            continue

        key = match.group(1)
        line = lines[index]
        index += 1

        if key == "status_line":
            value = line.split("=", 1)[1]
            if "[" in value and "]" not in value:
                while index < len(lines):
                    continuation = lines[index]
                    index += 1
                    if "]" in continuation:
                        break

    return "".join(output)


def render_managed_values(status_line: list[str], use_colors: bool) -> str:
    rendered = ["status_line = [\n"]
    rendered.extend(f'  "{item}",\n' for item in status_line)
    rendered.append("]\n")
    rendered.append(
        f"status_line_use_colors = {'true' if use_colors else 'false'}\n"
    )
    return "".join(rendered)


def merge_tui_section(config_text: str, managed_text: str) -> str:
    match = TUI_HEADER.search(config_text)
    if match is None:
        prefix = config_text.rstrip()
        separator = "\n\n" if prefix else ""
        return f"{prefix}{separator}[tui]\n{managed_text}"

    next_table = TABLE_HEADER.search(config_text, match.end())
    section_end = next_table.start() if next_table else len(config_text)
    body = config_text[match.end() : section_end]
    cleaned_body = remove_managed_assignments(body).strip("\n")

    replacement = match.group(0).rstrip("\r\n") + "\n" + managed_text
    if cleaned_body:
        replacement += "\n" + cleaned_body + "\n"
    elif section_end < len(config_text):
        replacement += "\n"

    return config_text[: match.start()] + replacement + config_text[section_end:]


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
            "Usage: merge_codex_statusline.py CONFIG_TOML STATUSLINE_SNIPPET_TOML",
            file=sys.stderr,
        )
        return 2

    target_path = Path(sys.argv[1]).expanduser()
    snippet_path = Path(sys.argv[2]).expanduser()
    snippet = tomllib.loads(snippet_path.read_text(encoding="utf-8"))
    tui = snippet.get("tui", {})

    status_line = tui.get("status_line")
    use_colors = tui.get("status_line_use_colors")
    if not isinstance(status_line, list) or not all(
        isinstance(item, str) for item in status_line
    ):
        raise ValueError("tui.status_line must be an array of strings")
    if not isinstance(use_colors, bool):
        raise ValueError("tui.status_line_use_colors must be a boolean")

    config_text = (
        target_path.read_text(encoding="utf-8") if target_path.exists() else ""
    )
    if config_text.strip():
        tomllib.loads(config_text)

    managed_text = render_managed_values(status_line, use_colors)
    merged_text = merge_tui_section(config_text, managed_text)
    tomllib.loads(merged_text)
    atomic_write(target_path, merged_text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
