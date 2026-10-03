#!/usr/bin/env python3
"""Bind an isolated Core build without persisting its client key in evidence."""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import sys

PROFILE = "core_acceptance_v1"
PRODUCTION = "production"
FORBIDDEN_PROJECTS = {"jcyqixttuebxqqfkjonq", "ivmvufhcsezyhczzondn"}
KEYS = (
    "profile", "sourceSha", "supabaseProjectRef", "supabaseUrl",
    "publishableKeySha256", "organizationId", "ownerApiBaseUrl",
    "projectRuntimeApiBaseUrl", "memoryMode",
)
SHA40 = re.compile(r"[a-f0-9]{40}\Z")
SHA256 = re.compile(r"[a-f0-9]{64}\Z")


class ConfigFailure(ValueError):
    """A fixed, content-free configuration error safe to report in CI."""


def require(condition: bool, code: str) -> None:
    if not condition:
        raise ConfigFailure(code)


def _unique_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        require(key not in result, "ACCEPTANCE_DUPLICATE_CONFIG_FIELD")
        result[key] = value
    return result


def read_json(value: str) -> dict:
    try:
        result = json.loads(value, object_pairs_hook=_unique_object)
    except (json.JSONDecodeError, TypeError):
        raise ConfigFailure("ACCEPTANCE_CONFIG_JSON_INVALID") from None
    require(isinstance(result, dict), "ACCEPTANCE_CONFIG_OBJECT_REQUIRED")
    return result


def canonical_config(value: dict, source_sha: str | None = None) -> dict[str, str]:
    require(isinstance(value, dict) and set(value) == set(KEYS),
            "ACCEPTANCE_CONFIG_FIELDS_INVALID")
    require(all(isinstance(value[key], str) for key in KEYS),
            "ACCEPTANCE_CONFIG_VALUES_INVALID")
    result = {key: value[key] for key in KEYS}
    require(result["profile"] == PROFILE, "ACCEPTANCE_PROFILE_REQUIRED")
    require(bool(SHA40.fullmatch(result["sourceSha"])), "ACCEPTANCE_SOURCE_INVALID")
    if source_sha is not None:
        require(result["sourceSha"] == source_sha, "ACCEPTANCE_SOURCE_MISMATCH")
    ref = result["supabaseProjectRef"]
    require(bool(re.fullmatch(r"[a-z0-9]{20}", ref)), "ACCEPTANCE_PROJECT_INVALID")
    require(ref not in FORBIDDEN_PROJECTS, "ACCEPTANCE_PRODUCTION_TARGET_REJECTED")
    url = "https://" + ref + ".supabase.co"
    require(result["supabaseUrl"] == url, "ACCEPTANCE_SUPABASE_URL_MISMATCH")
    require(result["ownerApiBaseUrl"] == url + "/functions/v1/pandora-owner-api"
            and result["projectRuntimeApiBaseUrl"] == url + "/functions/v1/pandora-project-runtime",
            "ACCEPTANCE_SERVICE_TARGET_MISMATCH")
    require(bool(re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}",
                              result["organizationId"])),
            "ACCEPTANCE_ORGANIZATION_INVALID")
    require(bool(SHA256.fullmatch(result["publishableKeySha256"])),
            "ACCEPTANCE_KEY_DIGEST_INVALID")
    require(result["memoryMode"] == "unavailable", "ACCEPTANCE_MEMORY_POLICY_INVALID")
    return result


def config_digest(value: dict) -> str:
    content = json.dumps(canonical_config(value), ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def validate_binding(value: dict, source_sha: str, expected_digest: str) -> dict[str, str]:
    config = canonical_config(value, source_sha)
    require(bool(SHA256.fullmatch(expected_digest or "")), "ACCEPTANCE_EXPECTED_DIGEST_REQUIRED")
    require(config_digest(config) == expected_digest, "ACCEPTANCE_CONFIG_DIGEST_MISMATCH")
    return config


def validate_client_key(key: str, config: dict) -> None:
    require(isinstance(key, str) and bool(key) and key == key.strip(),
            "ACCEPTANCE_CLIENT_KEY_REQUIRED")
    if not re.fullmatch(r"sb_publishable_[A-Za-z0-9_-]{16,}", key):
        try:
            parts = key.split(".")
            require(len(parts) == 3 and all(re.fullmatch(r"[A-Za-z0-9_-]+", part) for part in parts),
                    "ACCEPTANCE_PUBLIC_CLIENT_KEY_REQUIRED")
            payload = base64.urlsafe_b64decode(parts[1] + "=" * (-len(parts[1]) % 4))
            claims = read_json(payload.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            raise ConfigFailure("ACCEPTANCE_PUBLIC_CLIENT_KEY_REQUIRED") from None
        require(claims.get("role") == "anon"
                and claims.get("ref") == config["supabaseProjectRef"],
                "ACCEPTANCE_PUBLIC_CLIENT_KEY_REQUIRED")
    require(hashlib.sha256(key.encode("utf-8")).hexdigest() == config["publishableKeySha256"],
            "ACCEPTANCE_CLIENT_KEY_DIGEST_MISMATCH")


def protected_source_gate(environment: dict, source_sha: str, reviewed_source: str) -> None:
    require(bool(SHA40.fullmatch(source_sha or "")) and reviewed_source == source_sha,
            "ACCEPTANCE_REVIEWED_SOURCE_REQUIRED")
    rules = environment.get("protection_rules", [])
    require(isinstance(rules, list) and any(
        isinstance(rule, dict) and rule.get("type") == "required_reviewers"
        and isinstance(rule.get("reviewers"), list) and bool(rule["reviewers"])
        for rule in rules), "ACCEPTANCE_PROTECTED_ENVIRONMENT_REQUIRED")


def prepare_defines(profile: str, source_sha: str, app_version: str,
                    environment: dict, variables: dict[str, str]) -> tuple[dict, dict | None]:
    require(bool(SHA40.fullmatch(source_sha or "")), "ACCEPTANCE_SOURCE_INVALID")
    require(bool(re.fullmatch(r"[0-9A-Za-z.+-]+", app_version or "")), "ACCEPTANCE_VERSION_INVALID")
    defines = {"PANDORA_SOURCE_REVISION": source_sha, "PANDORA_APP_VERSION": app_version,
               "PANDORA_RUNTIME_PROFILE": profile}
    if profile == PRODUCTION:
        require(variables.get("PANDORA_CORE_QA_RUNTIME_PROFILE", "") in {"", PRODUCTION},
                "ACCEPTANCE_ORPHAN_BUILD_INPUT")
        require(not any(variables.get(name) for name in (
            "PANDORA_CORE_QA_TARGET_JSON", "PANDORA_CORE_QA_CONFIG_SHA256",
            "PANDORA_CORE_QA_SUPABASE_PUBLISHABLE_KEY")), "ACCEPTANCE_ORPHAN_BUILD_INPUT")
        return defines, None
    require(profile == PROFILE, "ACCEPTANCE_PROFILE_INVALID")
    require(variables.get("PANDORA_CORE_QA_RUNTIME_PROFILE") == PROFILE,
            "ACCEPTANCE_REVIEWED_PROFILE_REQUIRED")
    protected_source_gate(environment, source_sha, variables.get("PANDORA_CORE_QA_REVIEWED_SOURCE_SHA", ""))
    config = validate_binding(read_json(variables.get("PANDORA_CORE_QA_TARGET_JSON", "")),
                              source_sha, variables.get("PANDORA_CORE_QA_CONFIG_SHA256", ""))
    client_key = variables.get("PANDORA_CORE_QA_SUPABASE_PUBLISHABLE_KEY", "")
    validate_client_key(client_key, config)
    defines.update({
        "PANDORA_SUPABASE_URL": config["supabaseUrl"],
        "PANDORA_SUPABASE_PUBLISHABLE_KEY": client_key,
        "PANDORA_ORGANIZATION_ID": config["organizationId"],
        "PANDORA_OWNER_API_BASE_URL": config["ownerApiBaseUrl"],
        "PANDORA_PROJECT_RUNTIME_API_BASE_URL": config["projectRuntimeApiBaseUrl"],
        "PANDORA_ACCEPTANCE_SUPABASE_PROJECT_REF": config["supabaseProjectRef"],
        "PANDORA_ACCEPTANCE_ORGANIZATION_ID": config["organizationId"],
        "PANDORA_ACCEPTANCE_SOURCE_SHA": config["sourceSha"],
        "PANDORA_ACCEPTANCE_PUBLISHABLE_KEY_SHA256": config["publishableKeySha256"],
        "PANDORA_ACCEPTANCE_CONFIG_SHA256": config_digest(config),
    })
    return defines, config


def validate_reviewed_runtime(receipt: dict, source_sha: str, profile: str,
                              expected_digest: str, variables: dict[str, str]) -> None:
    require(receipt.get("source_sha") == source_sha
            and variables.get("PANDORA_CORE_QA_REVIEWED_SOURCE_SHA") == source_sha,
            "ACCEPTANCE_REVIEWED_SOURCE_REQUIRED")
    require(profile in {PRODUCTION, PROFILE}
            and receipt.get("runtime_profile", PRODUCTION) == profile
            and variables.get("PANDORA_CORE_QA_RUNTIME_PROFILE") == profile,
            "ACCEPTANCE_REVIEWED_PROFILE_REQUIRED")
    if profile == PRODUCTION:
        require(not expected_digest and not receipt.get("acceptance_config")
                and not receipt.get("acceptance_config_sha256")
                and not variables.get("PANDORA_CORE_QA_TARGET_JSON")
                and not variables.get("PANDORA_CORE_QA_CONFIG_SHA256"),
                "ACCEPTANCE_ORPHAN_RUNTIME_BINDING")
        return
    require(expected_digest == variables.get("PANDORA_CORE_QA_CONFIG_SHA256")
            and expected_digest == receipt.get("acceptance_config_sha256"),
            "ACCEPTANCE_REVIEWED_TARGET_REQUIRED")
    config = validate_binding(read_json(variables.get("PANDORA_CORE_QA_TARGET_JSON", "")),
                              source_sha, expected_digest)
    require(config == receipt.get("acceptance_config"), "ACCEPTANCE_REVIEWED_TARGET_REQUIRED")


def write_private_json(path: Path, value: dict) -> None:
    # Exclusive creation avoids overwriting an unexpected credential-bearing path.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as output:
        json.dump(value, output, ensure_ascii=False, separators=(",", ":"))
        output.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", required=True, choices=[PRODUCTION, PROFILE])
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--app-version", required=True)
    parser.add_argument("--environment-json", type=Path)
    parser.add_argument("--defines", type=Path, required=True)
    parser.add_argument("--binding", type=Path, required=True)
    parser.add_argument("--manifest-fields", type=Path, required=True)
    args = parser.parse_args()
    try:
        environment = read_json(args.environment_json.read_text()) if args.environment_json else {}
        defines, config = prepare_defines(args.profile, args.source_sha, args.app_version, environment, os.environ)
        write_private_json(args.defines, defines)
        fields = "runtime_profile=" + args.profile + "\n"
        if config is not None:
            # This document contains hashes and target identities, never the key.
            write_private_json(args.binding, config)
            fields += "acceptance_config_sha256=" + config_digest(config) + "\n"
        args.manifest_fields.write_text(fields, encoding="utf-8")
        print("CORE_RUNTIME_CONFIGURATION_BOUND")
        return 0
    except (ConfigFailure, OSError) as error:
        print(str(error) if isinstance(error, ConfigFailure) else "ACCEPTANCE_CONFIG_IO_FAILED", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
