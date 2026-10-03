"""Exercise target substitution, key containment and source-bound build inputs."""
import base64
import copy
import hashlib
import json
from pathlib import Path
import stat
import tempfile
import unittest

from core_acceptance_config import (
    ConfigFailure, FORBIDDEN_PROJECTS, PROFILE, canonical_config, config_digest,
    prepare_defines, protected_source_gate, read_json, validate_binding,
    validate_client_key, validate_reviewed_runtime, write_private_json,
)

FIXTURE = json.loads((Path(__file__).resolve().parents[1]
                     / "test/fixtures/core_acceptance_profile_v1.json").read_text())


class AcceptanceConfigurationTest(unittest.TestCase):
    def setUp(self):
        self.config = copy.deepcopy(FIXTURE["canonical"])
        self.key = FIXTURE["publishableKeyTestInput"]
        self.source = self.config["sourceSha"]
        self.environment = {"protection_rules": [{"type": "required_reviewers",
                            "reviewers": [{"type": "User", "reviewer": {"id": 123}}]}]}
        self.variables = {
            "PANDORA_CORE_QA_RUNTIME_PROFILE": PROFILE,
            "PANDORA_CORE_QA_REVIEWED_SOURCE_SHA": self.source,
            "PANDORA_CORE_QA_TARGET_JSON": json.dumps(self.config),
            "PANDORA_CORE_QA_CONFIG_SHA256": FIXTURE["configSha256"],
            "PANDORA_CORE_QA_SUPABASE_PUBLISHABLE_KEY": self.key,
        }

    def test_language_shared_hash_vector_and_key_order(self):
        reverse = dict(reversed(list(self.config.items())))
        actual = canonical_config(reverse)
        self.assertEqual(json.dumps(actual, separators=(",", ":")), FIXTURE["canonicalJson"])
        self.assertEqual(config_digest(actual), FIXTURE["configSha256"])
        self.assertEqual(validate_binding(actual, self.source, FIXTURE["configSha256"]), self.config)

    def test_build_defines_bind_every_mobile_target_and_keep_key_out_of_evidence(self):
        defines, binding = prepare_defines(PROFILE, self.source, "1.0.0+1", self.environment, self.variables)
        self.assertEqual(defines["PANDORA_SUPABASE_URL"], self.config["supabaseUrl"])
        self.assertEqual(defines["PANDORA_ORGANIZATION_ID"], self.config["organizationId"])
        self.assertEqual(defines["PANDORA_OWNER_API_BASE_URL"], self.config["ownerApiBaseUrl"])
        self.assertEqual(defines["PANDORA_PROJECT_RUNTIME_API_BASE_URL"], self.config["projectRuntimeApiBaseUrl"])
        self.assertEqual(defines["PANDORA_ACCEPTANCE_SOURCE_SHA"], self.source)
        self.assertEqual(defines["PANDORA_ACCEPTANCE_CONFIG_SHA256"], FIXTURE["configSha256"])
        self.assertEqual(defines["PANDORA_SUPABASE_PUBLISHABLE_KEY"], self.key)
        self.assertEqual(binding, self.config)
        self.assertNotIn(self.key, json.dumps(binding))

    def test_production_retains_defaults_but_rejects_orphan_inputs(self):
        defines, binding = prepare_defines("production", self.source, "1.0.0+1", {}, {})
        self.assertIsNone(binding)
        self.assertEqual(set(defines), {"PANDORA_RUNTIME_PROFILE", "PANDORA_SOURCE_REVISION", "PANDORA_APP_VERSION"})
        for key in ("PANDORA_CORE_QA_TARGET_JSON", "PANDORA_CORE_QA_CONFIG_SHA256", "PANDORA_CORE_QA_SUPABASE_PUBLISHABLE_KEY"):
            with self.subTest(key=key), self.assertRaisesRegex(ConfigFailure, "ORPHAN"):
                prepare_defines("production", self.source, "1.0.0+1", {}, {key: "supplied"})

    def test_both_production_projects_are_rejected_even_with_self_consistent_urls(self):
        for ref in FORBIDDEN_PROJECTS:
            config = {**self.config, "supabaseProjectRef": ref, "supabaseUrl": "https://" + ref + ".supabase.co"}
            config["ownerApiBaseUrl"] = config["supabaseUrl"] + "/functions/v1/pandora-owner-api"
            config["projectRuntimeApiBaseUrl"] = config["supabaseUrl"] + "/functions/v1/pandora-project-runtime"
            with self.subTest(ref=ref), self.assertRaisesRegex(ConfigFailure, "PRODUCTION_TARGET"):
                canonical_config(config)

    def test_target_source_hash_memory_and_shape_substitutions_rejected(self):
        substitutions = [
            ("profile", "production"), ("sourceSha", "a" * 39),
            ("supabaseProjectRef", "unreviewed.example"),
            ("supabaseUrl", "https://abcdefghijklmnopqrst.supabase.co:443"),
            ("supabaseUrl", "https://other.example"),
            ("ownerApiBaseUrl", self.config["ownerApiBaseUrl"] + "?redirect=main"),
            ("projectRuntimeApiBaseUrl", self.config["ownerApiBaseUrl"]),
            ("organizationId", "00000000-0000-0000-0000-000000000000"),
            ("organizationId", "10000000000040008000000000000001"),
            ("organizationId", "10000000-0000-7000-8000-000000000001"),
            ("organizationId", "10000000-0000-4000-1000-000000000001"),
            ("publishableKeySha256", "F" * 64), ("memoryMode", "production"),
        ]
        for key, value in substitutions:
            with self.subTest(key=key, value=value), self.assertRaises(ConfigFailure):
                canonical_config({**self.config, key: value})
        for config in ({**self.config, "unexpected": "value"}, {key: value for key, value in self.config.items() if key != "memoryMode"}):
            with self.assertRaisesRegex(ConfigFailure, "FIELDS"):
                canonical_config(config)
        for source, digest in (("b" * 40, FIXTURE["configSha256"]), (self.source, "b" * 64), (self.source, "")):
            with self.assertRaises(ConfigFailure):
                validate_binding(self.config, source, digest)

    def test_duplicate_fields_invalid_json_and_nonobjects_rejected(self):
        for value in ('{"sourceSha":"a","sourceSha":"b"}', '[{}]', 'null', '{invalid'):
            with self.subTest(value=value), self.assertRaises(ConfigFailure):
                read_json(value)

    def test_actual_reviewer_protection_and_exact_reviewed_source_required(self):
        protected_source_gate(self.environment, self.source, self.source)
        for environment, source in (({}, self.source), ({"protection_rules": [{"type": "required_reviewers", "reviewers": []}]}, self.source), (self.environment, "b" * 40)):
            with self.assertRaises(ConfigFailure):
                protected_source_gate(environment, self.source, source)

    def test_client_key_is_required_and_wrong_or_admin_material_not_embedded(self):
        validate_client_key(self.key, self.config)
        for key in ("", " " + self.key, self.key + "other", "sb_" + "secret_" + "x" * 24, "not-a-client-key"):
            with self.subTest(kind="invalid-client-material"), self.assertRaises(ConfigFailure) as caught:
                validate_client_key(key, self.config)
            self.assertNotIn(key or "never-print-key", str(caught.exception))

    def test_legacy_key_type_filter_requires_anon_and_same_project_not_authenticity(self):
        def segment(value):
            return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")
        for role, ref, accepted in (("anon", self.config["supabaseProjectRef"], True), ("service_role", self.config["supabaseProjectRef"], False), ("anon", "z" * 20, False)):
            key = ".".join((segment({"alg": "HS256"}), segment({"role": role, "ref": ref}), "unsigned_test_fixture"))
            config = {**self.config, "publishableKeySha256": hashlib.sha256(key.encode()).hexdigest()}
            if accepted:
                validate_client_key(key, config)
            else:
                with self.assertRaisesRegex(ConfigFailure, "PUBLIC_CLIENT_KEY"):
                    validate_client_key(key, config)

    def test_missing_protected_inputs_fail_before_any_defines_are_returned(self):
        for key in self.variables:
            variables = {name: value for name, value in self.variables.items() if name != key}
            with self.subTest(key=key), self.assertRaises(ConfigFailure):
                prepare_defines(PROFILE, self.source, "1.0.0+1", self.environment, variables)

    def test_private_defines_use_exclusive_creation_and_owner_only_mode(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "defines.json"
            write_private_json(path, {"client_material": self.key})
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(json.loads(path.read_text())["client_material"], self.key)
            with self.assertRaises(FileExistsError):
                write_private_json(path, {})

    def test_runtime_requires_independent_review_of_source_and_full_target(self):
        receipt = {"source_sha": self.source, "runtime_profile": PROFILE,
                   "acceptance_config_sha256": FIXTURE["configSha256"], "acceptance_config": self.config}
        validate_reviewed_runtime(receipt, self.source, PROFILE, FIXTURE["configSha256"], self.variables)
        for key, value in (("PANDORA_CORE_QA_CONFIG_SHA256", "a" * 64),
                           ("PANDORA_CORE_QA_REVIEWED_SOURCE_SHA", "b" * 40),
                           ("PANDORA_CORE_QA_RUNTIME_PROFILE", "production"),
                           ("PANDORA_CORE_QA_TARGET_JSON", "{}")):
            with self.subTest(key=key), self.assertRaises(ConfigFailure):
                validate_reviewed_runtime(receipt, self.source, PROFILE, FIXTURE["configSha256"], {**self.variables, key: value})
        with self.assertRaises(ConfigFailure):
            validate_reviewed_runtime({**receipt, "acceptance_config": {**self.config, "organizationId": "20000000-0000-4000-8000-000000000001"}},
                                      self.source, PROFILE, FIXTURE["configSha256"], self.variables)

    def test_production_runtime_cannot_accept_synthetic_target_approval(self):
        receipt = {"source_sha": self.source, "runtime_profile": "production"}
        approved = {"PANDORA_CORE_QA_REVIEWED_SOURCE_SHA": self.source,
                    "PANDORA_CORE_QA_RUNTIME_PROFILE": "production"}
        validate_reviewed_runtime(receipt, self.source, "production", "", approved)
        with self.assertRaises(ConfigFailure):
            validate_reviewed_runtime(receipt, self.source, "production", "", self.variables)


if __name__ == "__main__":
    unittest.main()
