#!/usr/bin/env python3
"""Verify an existing canonical Android artifact without rebuilding the app."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import stat
import sys
import zipfile
from pathlib import Path
from typing import Any

from core_acceptance_config import (
    ConfigFailure, PROFILE as ACCEPTANCE_PROFILE, read_json, validate_binding,
)

CANONICAL_REPOSITORY = "pandora-rvw-314296438-20260820/pandoras-box"
ANDROID_PACKAGE = "com.banataosystems.pandora_mobile"
MOBILE_WORKFLOW = ".github/workflows/pandora-mobile-integration.yml"
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
MAX_UNPACKED_BYTES = 1024 * 1024 * 1024


class ProvenanceError(ValueError):
    """A candidate cannot be attributed to the required source and build."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ProvenanceError(message)


def digest_file(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def read_manifest(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line:
            continue
        key, separator, value = line.partition("=")
        require(bool(separator) and bool(key), "Malformed artifact manifest.")
        require(key not in result, "Duplicate artifact manifest field.")
        result[key] = value
    return result


def extract_verified_archive(
    archive: Path, target: Path, archive_digest: str
) -> None:
    require(bool(SHA256.fullmatch(archive_digest)), "Invalid archive digest.")
    require(digest_file(archive) == archive_digest, "Archive digest mismatch.")
    require(not target.exists() or not any(target.iterdir()),
            "Extraction directory must be empty.")
    target.mkdir(parents=True, exist_ok=True)
    root = target.resolve()
    with zipfile.ZipFile(archive) as zipped:
        require(sum(item.file_size for item in zipped.infolist())
                <= MAX_UNPACKED_BYTES, "Artifact expands beyond the byte limit.")
        for item in zipped.infolist():
            path = Path(item.filename)
            require(not path.is_absolute() and ".." not in path.parts,
                    "Unsafe artifact archive path.")
            require(root in (target / path).resolve().parents,
                    "Artifact path escapes extraction directory.")
            require(not stat.S_ISLNK(item.external_attr >> 16),
                    "Symlinks are not allowed in Android artifacts.")
        zipped.extractall(target)


def verify_source_binding(
    expected_source: str, run: dict[str, Any],
    candidate_commit: dict[str, Any],
) -> dict[str, Any]:
    require(bool(SHA40.fullmatch(expected_source)), "Invalid exact source SHA.")
    require(run.get("repository", {}).get("full_name") == CANONICAL_REPOSITORY,
            "Workflow repository is not canonical.")
    require(run.get("head_repository", {}).get("full_name")
            == CANONICAL_REPOSITORY, "Fork artifacts are not accepted.")
    require(run.get("path") == MOBILE_WORKFLOW, "Unexpected mobile workflow.")
    require(run.get("status") == "completed"
            and run.get("conclusion") == "success",
            "Mobile build is not completed successfully.")
    event = run.get("event")
    require(event in {"push", "pull_request", "merge_group", "workflow_dispatch"},
            "Unsupported mobile build event.")
    head_sha = run.get("head_sha", "")
    require(bool(SHA40.fullmatch(head_sha)), "Invalid workflow head SHA.")
    require(candidate_commit.get("sha") == expected_source,
            "Candidate commit readback does not match the artifact source.")
    parents = [parent.get("sha") for parent in candidate_commit.get("parents", [])]
    if head_sha != expected_source:
        require(event in {"pull_request", "merge_group"},
                "Non-PR build source differs from its provider head.")
        require(head_sha in parents,
                "PR merge candidate is not a direct child of the build head.")
        binding = "verified-pr-merge-candidate"
    else:
        binding = "provider-head"
    return {"provider_head_sha": head_sha, "source_binding": binding,
            "workflow_event": event, "candidate_parent_shas": parents}


def verify_artifact(
    artifact_dir: Path, expected_source: str, run: dict[str, Any],
    artifact: dict[str, Any], candidate_commit: dict[str, Any],
    build_kind: str = "profile",
    expected_runtime_profile: str = "production",
    expected_config_sha256: str | None = None,
) -> dict[str, Any]:
    binding = verify_source_binding(expected_source, run, candidate_commit)
    require(build_kind in {"debug", "profile"}, "Unsupported candidate build kind.")
    require(artifact.get("expired") is False, "Workflow artifact is expired.")
    provider_run = artifact.get("workflow_run", {})
    require(provider_run.get("id") == run.get("id"),
            "Artifact does not belong to the selected mobile run.")
    require(provider_run.get("head_sha") == run.get("head_sha"),
            "Artifact provider head differs from the selected run.")
    allowed_names = {
        "pandora-mobile-android-validation-" + expected_source,
        "pandora-mobile-android-candidates-" + expected_source,
    }
    require(expected_runtime_profile in {"production", ACCEPTANCE_PROFILE},
            "Unexpected runtime profile.")
    if expected_runtime_profile == ACCEPTANCE_PROFILE:
        require(run.get("event") == "workflow_dispatch",
                "Isolated acceptance requires an explicit reviewed build.")
        allowed_names = {"pandora-mobile-android-core-acceptance-" + expected_source}
    else:
        require(not expected_config_sha256, "Production cannot use an acceptance digest.")
    require(artifact.get("name") in allowed_names,
            "Artifact name does not bind the exact built source.")
    manifests = list(artifact_dir.rglob("pandora-mobile-artifact-manifest.txt"))
    require(len(manifests) == 1, "Exactly one source manifest is required.")
    manifest = read_manifest(manifests[0])
    runtime_profile = manifest.get("runtime_profile", "production")
    require(runtime_profile == expected_runtime_profile, "Artifact runtime profile mismatch.")
    acceptance_config = None
    binding_files = list(artifact_dir.rglob("pandora-core-acceptance-binding.json"))
    if runtime_profile == ACCEPTANCE_PROFILE:
        require(len(binding_files) == 1, "Exactly one isolated target binding is required.")
        require(manifest.get("acceptance_config_sha256") == expected_config_sha256,
                "Artifact target digest differs from the independently expected target.")
        try:
            acceptance_config = validate_binding(read_json(binding_files[0].read_text(encoding="utf-8")),
                                                 expected_source, expected_config_sha256 or "")
        except ConfigFailure as error:
            raise ProvenanceError(str(error)) from None
    else:
        require(not binding_files and not manifest.get("acceptance_config_sha256"),
                "Production artifact contains orphan isolated target metadata.")
    require(manifest.get("source_sha") == expected_source,
            "Artifact manifest source differs from expected source.")
    require(manifest.get("source_tree")
            == candidate_commit.get("commit", {}).get("tree", {}).get("sha")
            and bool(SHA40.fullmatch(manifest.get("source_tree", ""))),
            "Artifact source tree differs from the provider commit.")
    require(manifest.get("workflow_run_id") == str(run.get("id")),
            "Artifact manifest belongs to another workflow run.")
    require(manifest.get("workflow_run_attempt") == str(run.get("run_attempt")),
            "Artifact manifest belongs to another build attempt.")
    require(manifest.get("android_package") == ANDROID_PACKAGE,
            "Artifact package is not the generic core Pandora app.")
    require(manifest.get("artifact_class") == "validation-candidate",
            "Unexpected Android artifact classification.")
    require(manifest.get("production_release") == "false",
            "This workflow verifies a candidate, not a production claim.")
    require(manifest.get("android_artifact_name") == artifact.get("name"),
            "Manifest artifact name differs from its provider.")
    app_version = manifest.get("app_version", "")
    require(bool(re.fullmatch(r"[0-9A-Za-z.+-]+", app_version)),
            "Missing or invalid candidate version.")
    apks = list(artifact_dir.rglob("app-" + build_kind + ".apk"))
    require(len(apks) == 1, "Exactly one matching candidate APK is required.")
    apk = apks[0]
    prefix = "profile_apk" if build_kind == "profile" else "apk"
    expected_digest = manifest.get(prefix + "_sha256", "")
    require(bool(SHA256.fullmatch(expected_digest)), "Missing candidate APK digest.")
    require(digest_file(apk) == expected_digest, "Candidate APK digest mismatch.")
    require(str(apk.stat().st_size) == manifest.get(prefix + "_size_bytes"),
            "Candidate APK byte size mismatch.")
    return {
        "schema": "pandora-core-android-artifact-v1",
        "repository": CANONICAL_REPOSITORY,
        "source_sha": expected_source,
        "source_tree_sha": manifest.get("source_tree"),
        "workflow_run_id": run["id"],
        "workflow_run_attempt": manifest.get("workflow_run_attempt"),
        "artifact_id": artifact["id"],
        "artifact_name": artifact["name"],
        "artifact_archive_sha256": str(artifact.get("digest", "")).removeprefix("sha256:"),
        "apk_path": str(apk.resolve()),
        "apk_sha256": expected_digest,
        "apk_bytes": apk.stat().st_size,
        "android_package": ANDROID_PACKAGE,
        "app_version": app_version,
        "build_kind": build_kind,
        "artifact_class": "validation-candidate",
        "runtime_profile": runtime_profile,
        "acceptance_config_sha256": expected_config_sha256 if acceptance_config else None,
        "acceptance_config": acceptance_config,
        "installed": False,
        "runtime_verified": False,
        "production_verified": False,
        **binding,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--runtime-profile", default="production",
                        choices=["production", ACCEPTANCE_PROFILE])
    parser.add_argument("--config-sha256", default="")
    parser.add_argument("--run-json", type=Path, required=True)
    parser.add_argument("--artifact-json", type=Path, required=True)
    parser.add_argument("--commit-json", type=Path, required=True)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--extract-dir", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--build-kind", choices=["debug", "profile"], default="profile")
    args = parser.parse_args()
    try:
        run = json.loads(args.run_json.read_text())
        artifact = json.loads(args.artifact_json.read_text())
        candidate = json.loads(args.commit_json.read_text())
        digest = str(artifact.get("digest", "")).removeprefix("sha256:")
        extract_verified_archive(args.archive, args.extract_dir, digest)
        receipt = verify_artifact(args.extract_dir, args.source_sha, run, artifact,
                                  candidate, args.build_kind, args.runtime_profile,
                                  args.config_sha256 or None)
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(json.dumps(receipt, indent=2) + "\n")
        print(json.dumps({"result": "artifact-verified",
                          "source_sha": receipt["source_sha"],
                          "apk_sha256": receipt["apk_sha256"],
                          "build_kind": receipt["build_kind"]}))
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        print("CORE_ARTIFACT_REJECTED: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
