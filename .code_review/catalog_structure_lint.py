#!/usr/bin/env python3
"""Small dependency-free structural checks for the NKP AI catalog.

NuReviewer invokes this script from the repository root and appends the
matching changed files as positional arguments. Keep stdout limited to one
NuReviewer JSON object; diagnostics belong on stderr.

This is intentionally conservative. Extend it only with checks that are
stable, deterministic, and low-noise.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any


REQUIRED_METADATA_FIELDS = (
    "schema",
    "displayName",
    "description",
    "category",
    "licensing",
    "scope",
    "overview",
    "supportLink",
    "type",
    "dependencies",
    "requiredDependencies",
    "icon",
    "allowMultipleInstances",
)

TOP_LEVEL_KEY = re.compile(r"^([A-Za-z][A-Za-z0-9_-]*):(?:\s|$)")


def violation(
    path: str,
    line: int,
    rule: str,
    message: str,
    severity: str = "MAJOR",
) -> dict[str, Any]:
    return {
        "file": path,
        "line": line,
        "rule": rule,
        "message": message,
        "severity": severity,
    }


def top_level_keys(lines: list[str]) -> set[str]:
    keys: set[str] = set()
    for raw in lines:
        match = TOP_LEVEL_KEY.match(raw.rstrip("\n"))
        if match:
            keys.add(match.group(1))
    return keys


def check_yaml(path: str, text: str) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    lines = text.splitlines()

    if "\t" in text:
        line = next(i for i, raw in enumerate(lines, start=1) if "\t" in raw)
        findings.append(
            violation(
                path,
                line,
                "YAML_TABS",
                "Use spaces rather than tab characters for YAML indentation.",
                "MAJOR",
            )
        )

    if lines and lines[-1].strip() != "---":
        findings.append(
            violation(
                path,
                len(lines),
                "YAML_DOCUMENT_SEPARATOR",
                "End every YAML document with '---' on its own line.",
                "MINOR",
            )
        )

    for number, raw in enumerate(lines, start=1):
        if re.match(r"^\s*targetNamespace:\s*(default|kommander|workspace)\s*$", raw):
            findings.append(
                violation(
                    path,
                    number,
                    "HARDCODED_TARGET_NAMESPACE",
                    "Use the application's dedicated namespace instead of a shared default namespace.",
                    "MAJOR",
                )
            )
        if re.match(r"^\s*namespace:\s*(default)\s*$", raw):
            findings.append(
                violation(
                    path,
                    number,
                    "DEFAULT_NAMESPACE",
                    "Do not deploy catalog resources into the default namespace.",
                    "MAJOR",
                )
            )
        if "targetNamespace: ${releaseNamespace}" in raw:
            findings.append(
                violation(
                    path,
                    number,
                    "RELEASE_NAMESPACE_TARGET",
                    "Use a dedicated application target namespace rather than ${releaseNamespace}.",
                    "MAJOR",
                )
            )

    return findings


def check_metadata(path: str, text: str) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    lines = text.splitlines()
    keys = top_level_keys(lines)

    for field in REQUIRED_METADATA_FIELDS:
        if field not in keys:
            findings.append(
                violation(
                    path,
                    1,
                    "METADATA_REQUIRED_FIELD",
                    f"metadata.yaml must define the required top-level field '{field}'.",
                    "MAJOR",
                )
            )

    schema_lines = [
        (number, raw)
        for number, raw in enumerate(lines, start=1)
        if raw.startswith("schema:")
    ]
    if schema_lines and "catalog.nkp.nutanix.com/v1/application-metadata" not in schema_lines[0][1]:
        findings.append(
            violation(
                path,
                schema_lines[0][0],
                "METADATA_SCHEMA",
                "Use schema catalog.nkp.nutanix.com/v1/application-metadata.",
                "MAJOR",
            )
        )

    return findings


def check_kustomization(path: str, text: str) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    file_path = Path(path)
    if file_path.name != "kustomization.yaml" or file_path.parent.name != "helmrelease":
        return findings

    namespace_file = file_path.parent / "namespace.yaml"
    if namespace_file.exists() and not re.search(r"^\s*-\s*namespace\.yaml\s*$", text, re.MULTILINE):
        findings.append(
            violation(
                path,
                1,
                "KUSTOMIZATION_NAMESPACE",
                "Include namespace.yaml in helmrelease/kustomization.yaml when the file exists.",
                "MAJOR",
            )
        )
    return findings


def main(argv: list[str]) -> int:
    findings: list[dict[str, Any]] = []

    for raw_path in argv[1:]:
        path = Path(raw_path)
        if not path.is_file() or path.suffix not in {".yaml", ".yml"}:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue

        normalized_path = path.as_posix()
        findings.extend(check_yaml(normalized_path, text))
        if path.name == "metadata.yaml":
            findings.extend(check_metadata(normalized_path, text))
        findings.extend(check_kustomization(normalized_path, text))

    print(json.dumps({"violations": findings}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
