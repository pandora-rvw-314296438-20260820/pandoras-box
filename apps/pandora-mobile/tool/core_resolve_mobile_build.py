#!/usr/bin/env python3
"""Resolve a completed PR mobile artifact by compiled SHA, never by head alone."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time
from core_artifact_provenance import CANONICAL_REPOSITORY, MOBILE_WORKFLOW, SHA40


def matching_runs(runs: list[dict], provider_head: str) -> list[dict]:
    return sorted((run for run in runs
                   if run.get("path") == MOBILE_WORKFLOW
                   and run.get("head_sha") == provider_head
                   and run.get("event") == "pull_request"
                   and run.get("head_repository", {}).get("full_name") == CANONICAL_REPOSITORY),
                  key=lambda run: run["id"], reverse=True)


def matching_artifact(artifacts: list[dict], source_sha: str) -> dict | None:
    names = {"pandora-mobile-android-validation-" + source_sha,
             "pandora-mobile-android-candidates-" + source_sha}
    matches = [artifact for artifact in artifacts
               if artifact.get("name") in names and artifact.get("expired") is False]
    if len(matches) > 1:
        raise RuntimeError("AMBIGUOUS_EXACT_SOURCE_ARTIFACT")
    return matches[0] if matches else None


def api(path: str):
    result = subprocess.run(["gh", "api", path], capture_output=True, text=True, timeout=45)
    if result.returncode:
        raise RuntimeError("GITHUB_ARTIFACT_READBACK_FAILED")
    return json.loads(result.stdout)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--provider-head-sha", required=True)
    parser.add_argument("--output", type=Path, required=True)
    # The separate workflow includes Android and iOS jobs with 40-minute
    # limits. Allow queue time too; the enclosing runtime job is 90 minutes.
    parser.add_argument("--timeout", type=int, default=3600)
    args = parser.parse_args()
    if not SHA40.fullmatch(args.source_sha) or not SHA40.fullmatch(args.provider_head_sha):
        raise SystemExit("EXACT_SOURCE_AND_PROVIDER_HEAD_REQUIRED")
    until = time.monotonic() + args.timeout
    try:
        while time.monotonic() < until:
            runs = api(f"repos/{CANONICAL_REPOSITORY}/actions/runs?event=pull_request&head_sha={args.provider_head_sha}&per_page=50")
            for run in matching_runs(runs.get("workflow_runs", []), args.provider_head_sha):
                if run.get("status") != "completed" or run.get("conclusion") != "success":
                    continue
                artifacts = api(f"repos/{CANONICAL_REPOSITORY}/actions/runs/{run['id']}/artifacts?per_page=100")
                artifact = matching_artifact(artifacts.get("artifacts", []), args.source_sha)
                if artifact:
                    args.output.parent.mkdir(parents=True, exist_ok=True)
                    result = {"source_sha": args.source_sha, "provider_head_sha": args.provider_head_sha,
                              "build_run_id": run["id"], "artifact_id": artifact["id"]}
                    args.output.write_text(json.dumps(result, indent=2) + "\n")
                    if output := os.environ.get("GITHUB_ENV"):
                        with open(output, "a") as target:
                            target.write(f"BUILD_RUN_ID={run['id']}\nARTIFACT_ID={artifact['id']}\n")
                    print(json.dumps(result))
                    return 0
            time.sleep(20)
        raise RuntimeError("EXACT_SOURCE_MOBILE_ARTIFACT_NOT_READY")
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error) if isinstance(error, RuntimeError) else type(error).__name__)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
