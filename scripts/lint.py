#!/usr/bin/env python3
"""Repository integrity lint; --swift also asks Xcode to parse Swift syntax."""

import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
TEXT_SUFFIXES = {
    ".swift", ".py", ".sh", ".md", ".yml", ".yaml", ".json", ".plist",
    ".pbxproj", ".xcscheme", ".xcworkspacedata",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swift", action="store_true", help="Parse Swift syntax using Xcode (macOS only)")
    args = parser.parse_args()
    errors = []
    listed = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT
    ).decode("utf-8").split("\0")
    paths = sorted({ROOT / name for name in listed if name and (ROOT / name).is_file()})
    for path in paths:
        if path.suffix not in TEXT_SUFFIXES and path.name != ".gitignore":
            continue
        relative = path.relative_to(ROOT)
        text = path.read_text(encoding="utf-8")
        if text and not text.endswith("\n"):
            errors.append(f"{relative}: missing final newline")
        for number, line in enumerate(text.splitlines(), 1):
            if line.rstrip() != line:
                errors.append(f"{relative}:{number}: trailing whitespace")
            if re.match(r"^(<<<<<<< |=======$|>>>>>>> )", line):
                errors.append(f"{relative}:{number}: merge conflict marker")
        try:
            if path.suffix == ".json":
                json.loads(text)
            elif path.suffix == ".plist":
                plistlib.loads(path.read_bytes())
            elif path.suffix in {".xcscheme", ".xcworkspacedata"}:
                ET.fromstring(text)
        except (ValueError, ET.ParseError, plistlib.InvalidFileException) as error:
            errors.append(f"{relative}: {error}")

    project = (ROOT / "LiftRank.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    phases = dict(re.findall(
        r"(\w+) /\* Sources \*/ = \{\s*isa = PBXSourcesBuildPhase;.*?files = \((.*?)\);",
        project, re.S,
    ))
    for target in ("LiftRank", "LiftRankTests"):
        match = re.search(
            rf"\w+ /\* {target} \*/ = \{{\s*isa = PBXNativeTarget;.*?buildPhases = \((.*?)\);",
            project, re.S,
        )
        if not match:
            errors.append(f"Xcode project: missing {target} target")
            continue
        source_phases = re.findall(r"(\w+) /\* Sources \*/", match.group(1))
        included = [
            name
            for phase in source_phases
            for name in re.findall(r"/\* ([^*]+\.swift) in Sources \*/", phases.get(phase, ""))
        ]
        expected = {path.name for path in (ROOT / target).rglob("*.swift")}
        if set(included) != expected or len(included) != len(expected):
            errors.append(
                f"{target}: source membership mismatch; missing={sorted(expected - set(included))}, "
                f"extra={sorted(set(included) - expected)}, duplicates={len(included) - len(set(included))}"
            )

    scheme = ET.parse(ROOT / "LiftRank.xcodeproj/xcshareddata/xcschemes/LiftRank.xcscheme")
    test_targets = {node.attrib.get("BlueprintName") for node in scheme.findall(".//TestableReference/BuildableReference")}
    if "LiftRankTests" not in test_targets:
        errors.append("LiftRank scheme: regression tests are not enabled")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("Repository lint passed (whitespace, conflict markers, structured files, Xcode source membership and test scheme).")
    if args.swift:
        for directory in ("LiftRank", "LiftRankTests"):
            sources = sorted(str(path) for path in (ROOT / directory).rglob("*.swift"))
            subprocess.run(["xcrun", "swiftc", "-frontend", "-parse", *sources], check=True, cwd=ROOT)
        print("Swift syntax checks passed. Type checking and runtime coverage require xcodebuild test.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
