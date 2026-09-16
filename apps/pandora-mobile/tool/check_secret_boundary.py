#!/usr/bin/env python3
"""Fail-closed Pandora Mobile secret-boundary scanner.

Reports only rule ids, locations, line numbers, and SHA-256 fingerprints.
Matched credential material is never printed.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

_ALLOWED_DART_DEFINES = frozenset({"PANDORA_SUPABASE_PUBLISHABLE_KEY"})
_TEXT_SUFFIXES = frozenset({
    ".dart", ".yaml", ".yml", ".json", ".xml", ".gradle", ".kts",
    ".properties", ".md", ".txt", ".sh", ".py", ".toml",
})

_FORBIDDEN_IDENTIFIER = re.compile(
    rb"(?i)(?<![A-Za-z0-9_])(?:"
    rb"GITHUB_PAT|GITHUB_TOKEN|GITHUB_SUPABASE|OPENAI_API_KEY|"
    rb"AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN|"
    rb"SUPABASE_SERVICE_ROLE|SUPABASE_SERVICE_ROLE_KEY|VERCEL_TOKEN|"
    rb"GEMINI_API_KEY|ANTHROPIC_API_KEY|MOONSHOT_API_KEY|KIMI_API_KEY|"
    rb"DATABASE_PASSWORD"
    rb")(?![A-Za-z0-9_])"
)

_LITERAL_RULES = (
    ("private_key_marker", re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")),
    ("github_pat_literal", re.compile(rb"(?i)(?:github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,})")),
    ("openai_style_secret_literal", re.compile(rb"(?i)\bsk-[A-Za-z0-9_-]{20,}\b")),
    ("google_api_secret_literal", re.compile(rb"\bAIza[0-9A-Za-z_-]{20,}\b")),
    ("aws_access_key_literal", re.compile(rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")),
    ("supabase_secret_literal", re.compile(rb"\bsb_secret_[A-Za-z0-9_-]{20,}\b")),
    ("bearer_credential_literal", re.compile(rb"(?i)\bBearer[ \t]+[A-Za-z0-9._~+/\-]{20,}=*\b")),
)

_ACTIONS_SECRET = re.compile(rb"\$\{\{\s*secrets\.[A-Za-z_][A-Za-z0-9_]*\s*\}\}")
_DART_DEFINE = re.compile(rb"--dart-define(?:=|[ \t]+)([A-Za-z_][A-Za-z0-9_]*)")


@dataclass(frozen=True)
class Finding:
    rule: str
    location: str
    line: int
    fingerprint: str


def _fingerprint(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()[:16]


def _line_number(data: bytes, offset: int) -> int:
    return data.count(b"\n", 0, offset) + 1


def scan_bytes(data: bytes, *, location: str) -> list[Finding]:
    findings: list[Finding] = []

    for match in _FORBIDDEN_IDENTIFIER.finditer(data):
        findings.append(Finding(
            "forbidden_provider_secret_identifier",
            location,
            _line_number(data, match.start()),
            _fingerprint(match.group(0).lower()),
        ))

    for rule, pattern in _LITERAL_RULES:
        for match in pattern.finditer(data):
            findings.append(Finding(
                rule,
                location,
                _line_number(data, match.start()),
                _fingerprint(match.group(0)),
            ))

    for match in _ACTIONS_SECRET.finditer(data):
        findings.append(Finding(
            "github_actions_secret_injection",
            location,
            _line_number(data, match.start()),
            _fingerprint(match.group(0).lower()),
        ))

    for match in _DART_DEFINE.finditer(data):
        name = match.group(1).decode("ascii", errors="ignore")
        upper = name.upper()
        if name in _ALLOWED_DART_DEFINES:
            continue
        if any(marker in upper for marker in ("KEY", "TOKEN", "SECRET", "PASSWORD")):
            findings.append(Finding(
                "sensitive_dart_define",
                location,
                _line_number(data, match.start()),
                _fingerprint(match.group(0).lower()),
            ))

    return findings


def _iter_source_files(target: Path) -> Iterable[Path]:
    if target.is_file():
        yield target
        return
    if not target.is_dir():
        raise FileNotFoundError(str(target))
    for path in sorted(target.rglob("*")):
        if not path.is_file():
            continue
        if any(part in {".git", "build", ".dart_tool"} for part in path.parts):
            continue
        if path.suffix.lower() in _TEXT_SUFFIXES or path.name == "pubspec.lock":
            yield path


def scan_source_targets(targets: Iterable[Path]) -> list[Finding]:
    findings: list[Finding] = []
    for target in targets:
        for path in _iter_source_files(target):
            try:
                data = path.read_bytes()
            except OSError as exc:
                raise RuntimeError(f"unable to read scan target: {path}") from exc
            findings.extend(scan_bytes(data, location=path.as_posix()))
    return findings


def render_findings(findings: Iterable[Finding]) -> str:
    return "\n".join(
        f"{finding.rule} location={finding.location} line={finding.line} "
        f"fingerprint={finding.fingerprint}"
        for finding in findings
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Scan Pandora Mobile sources for forbidden long-lived credential material."
    )
    parser.add_argument("targets", nargs="+", type=Path)
    args = parser.parse_args(argv)

    try:
        findings = scan_source_targets(args.targets)
    except (FileNotFoundError, RuntimeError) as exc:
        print(f"Pandora Mobile secret-boundary scan could not complete: {exc}", file=sys.stderr)
        return 2

    if findings:
        print("Pandora Mobile secret-boundary scan FAILED.", file=sys.stderr)
        print(render_findings(findings), file=sys.stderr)
        return 1

    print("Pandora Mobile secret-boundary scan passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
