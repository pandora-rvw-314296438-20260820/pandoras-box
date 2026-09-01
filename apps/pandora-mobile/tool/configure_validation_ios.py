#!/usr/bin/env python3
"""Register Pandora's exact-preview Swift source in a disposable Flutter iOS project."""

from __future__ import annotations

import argparse
from pathlib import Path

FILE_REF = "A14900000000000000000001"
BUILD_REF = "A14900000000000000000002"
FILE_NAME = "PandoraExactPreviewView.swift"


def _section(text: str, begin: str, end: str) -> tuple[int, int, str]:
    start = text.find(begin)
    finish = text.find(end)
    if start < 0 or finish < 0 or finish <= start:
        raise SystemExit(f"Unexpected Xcode project structure: {begin}")
    finish += len(end)
    return start, finish, text[start:finish]


def configure(project_file: Path) -> None:
    text = project_file.read_text(encoding="utf-8")

    if FILE_REF in text or BUILD_REF in text:
        if text.count(FILE_REF) == 3 and text.count(BUILD_REF) == 2:
            return
        raise SystemExit("Pandora iOS project registration is partially present.")

    build_begin = "/* Begin PBXBuildFile section */"
    file_begin = "/* Begin PBXFileReference section */"
    if text.count(build_begin) != 1 or text.count(file_begin) != 1:
        raise SystemExit("Unexpected Xcode project sections.")

    build_entry = (
        f"\n\t\t{BUILD_REF} /* {FILE_NAME} in Sources */ = "
        f"{{isa = PBXBuildFile; fileRef = {FILE_REF} /* {FILE_NAME} */; }};"
    )
    file_entry = (
        f"\n\t\t{FILE_REF} /* {FILE_NAME} */ = "
        "{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
        f"path = {FILE_NAME}; sourceTree = \"<group>\"; }};"
    )
    text = text.replace(build_begin, build_begin + build_entry, 1)
    text = text.replace(file_begin, file_begin + file_entry, 1)

    _, _, groups = _section(
        text, "/* Begin PBXGroup section */", "/* End PBXGroup section */"
    )
    group_lines = [
        line
        for line in groups.splitlines()
        if "/* AppDelegate.swift */," in line and "in Sources" not in line
    ]
    if len(group_lines) != 1:
        raise SystemExit("Expected exactly one Runner AppDelegate.swift group entry.")
    group_line = group_lines[0]
    text = text.replace(
        group_line,
        group_line + f"\n\t\t\t\t{FILE_REF} /* {FILE_NAME} */,",
        1,
    )

    _, _, sources = _section(
        text,
        "/* Begin PBXSourcesBuildPhase section */",
        "/* End PBXSourcesBuildPhase section */",
    )
    source_lines = [
        line for line in sources.splitlines() if "/* AppDelegate.swift in Sources */," in line
    ]
    if len(source_lines) != 1:
        raise SystemExit("Expected exactly one AppDelegate.swift Sources entry.")
    source_line = source_lines[0]
    text = text.replace(
        source_line,
        source_line + f"\n\t\t\t\t{BUILD_REF} /* {FILE_NAME} in Sources */,",
        1,
    )

    if text.count(FILE_REF) != 3 or text.count(BUILD_REF) != 2:
        raise SystemExit("Pandora iOS project registration did not converge.")

    project_file.write_text(text, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("project_file", type=Path)
    args = parser.parse_args()
    configure(args.project_file)


if __name__ == "__main__":
    main()
