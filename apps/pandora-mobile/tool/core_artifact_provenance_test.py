"""Exercise source/artifact substitution and exact-byte provenance boundaries."""
import copy
import hashlib
import json
from pathlib import Path
import stat
import tempfile
import unittest
import zipfile

from core_artifact_provenance import (
    CANONICAL_REPOSITORY, MOBILE_WORKFLOW, ProvenanceError,
    extract_verified_archive, read_manifest, verify_artifact,
    verify_source_binding,
)
from core_acceptance_config import PROFILE, config_digest

SOURCE = "a" * 40
HEAD = "b" * 40


class ArtifactProvenanceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.run = {
            "id": 91, "run_attempt": 1, "head_sha": SOURCE, "event": "push", "status": "completed",
            "conclusion": "success", "path": MOBILE_WORKFLOW,
            "repository": {"full_name": CANONICAL_REPOSITORY},
            "head_repository": {"full_name": CANONICAL_REPOSITORY},
        }
        self.commit = {"sha": SOURCE, "parents": [{"sha": "c" * 40}],
                       "commit": {"tree": {"sha": "e" * 40}}}
        self.artifact = {
            "id": 92, "name": "pandora-mobile-android-validation-" + SOURCE,
            "expired": False, "digest": "sha256:" + "d" * 64,
            "workflow_run": {"id": 91, "head_sha": SOURCE},
        }
        self.debug = b"exact-debug-apk-fixture"
        self.profile = b"exact-profile-apk-fixture"
        (self.root / "app-debug.apk").write_bytes(self.debug)
        (self.root / "app-profile.apk").write_bytes(self.profile)
        self.fields = {
            "source_sha": SOURCE, "source_tree": "e" * 40,
            "workflow_run_id": "91", "workflow_run_attempt": "1",
            "android_artifact_name": self.artifact["name"],
            "android_package": "com.banataosystems.pandora_mobile",
            "artifact_class": "validation-candidate", "production_release": "false",
            "app_version": "0.4.0-rc.14+21",
            "apk_sha256": hashlib.sha256(self.debug).hexdigest(),
            "apk_size_bytes": str(len(self.debug)),
            "profile_apk_sha256": hashlib.sha256(self.profile).hexdigest(),
            "profile_apk_size_bytes": str(len(self.profile)),
        }
        self.write_manifest()

    def write_manifest(self):
        self.manifest = self.root / "pandora-mobile-artifact-manifest.txt"
        self.manifest.write_text("".join(f"{k}={v}\n" for k, v in self.fields.items()))

    def verify(self, kind="profile", **kwargs):
        return verify_artifact(self.root, SOURCE, self.run, self.artifact,
                               self.commit, kind, **kwargs)

    def acceptance_candidate(self):
        fixture = json.loads((Path(__file__).resolve().parents[1]
                              / "test/fixtures/core_acceptance_profile_v1.json").read_text())
        self.config = {**fixture["canonical"], "sourceSha": SOURCE}
        self.config_sha = config_digest(self.config)
        self.binding_file = self.root / "pandora-core-acceptance-binding.json"
        self.binding_file.write_text(json.dumps(self.config))
        self.run["event"] = "workflow_dispatch"
        self.artifact["name"] = "pandora-mobile-android-core-acceptance-" + SOURCE
        self.fields.update(runtime_profile=PROFILE, acceptance_config_sha256=self.config_sha,
                           android_artifact_name=self.artifact["name"])
        self.write_manifest()

    def verify_acceptance(self):
        return self.verify(expected_runtime_profile=PROFILE, expected_config_sha256=self.config_sha)

    def test_isolated_artifact_requires_explicit_profile_and_independent_target_digest(self):
        self.acceptance_candidate()
        with self.assertRaises(ProvenanceError):
            self.verify()
        with self.assertRaises(ProvenanceError):
            self.verify(expected_runtime_profile=PROFILE)
        receipt = self.verify_acceptance()
        self.assertEqual(receipt["runtime_profile"], PROFILE)
        self.assertEqual(receipt["acceptance_config_sha256"], self.config_sha)
        self.assertEqual(receipt["acceptance_config"], self.config)
        self.assertFalse(receipt["runtime_verified"])
        self.assertFalse(receipt["production_verified"])

    def test_isolated_target_substitution_rejected_even_at_identical_source(self):
        self.acceptance_candidate()
        for mutation in ({**self.config, "organizationId": "20000000-0000-4000-8000-000000000001"},
                         {**self.config, "sourceSha": HEAD}, {**self.config, "memoryMode": "production"}):
            self.binding_file.write_text(json.dumps(mutation))
            with self.assertRaises(ProvenanceError):
                self.verify_acceptance()
        self.binding_file.write_text(json.dumps(self.config))
        self.fields["acceptance_config_sha256"] = "b" * 64
        self.write_manifest()
        with self.assertRaises(ProvenanceError):
            self.verify_acceptance()

    def test_isolated_artifact_cannot_use_push_or_canonical_name(self):
        self.acceptance_candidate()
        self.run["event"] = "push"
        with self.assertRaises(ProvenanceError):
            self.verify_acceptance()
        self.run["event"] = "workflow_dispatch"
        self.artifact["name"] = "pandora-mobile-android-validation-" + SOURCE
        self.fields["android_artifact_name"] = self.artifact["name"]
        self.write_manifest()
        with self.assertRaises(ProvenanceError):
            self.verify_acceptance()

    def test_missing_duplicate_or_private_binding_fields_are_rejected(self):
        self.acceptance_candidate()
        self.binding_file.unlink()
        with self.assertRaises(ProvenanceError):
            self.verify_acceptance()
        self.binding_file.write_text(json.dumps({**self.config, "client_key": "test-material-must-never-be-in-evidence"}))
        with self.assertRaises(ProvenanceError):
            self.verify_acceptance()
        self.binding_file.write_text(json.dumps(self.config))
        second = self.root / "duplicate"
        second.mkdir()
        (second / self.binding_file.name).write_text(json.dumps(self.config))
        with self.assertRaises(ProvenanceError):
            self.verify_acceptance()

    def test_production_manifest_cannot_carry_orphan_acceptance_metadata(self):
        self.fields["acceptance_config_sha256"] = "a" * 64
        self.write_manifest()
        with self.assertRaises(ProvenanceError):
            self.verify()

    def test_exact_profile_bytes_and_source_do_not_claim_runtime(self):
        receipt = self.verify()
        self.assertEqual(receipt["apk_sha256"], self.fields["profile_apk_sha256"])
        self.assertEqual(receipt["source_binding"], "provider-head")
        self.assertEqual(receipt["source_sha"], SOURCE)
        self.assertFalse(receipt["installed"])
        self.assertFalse(receipt["runtime_verified"])
        self.assertFalse(receipt["production_verified"])

    def test_debug_selection_is_bound_to_debug_bytes(self):
        self.assertEqual(self.verify("debug")["apk_sha256"], self.fields["apk_sha256"])

    def test_pr_provider_head_and_compiled_merge_source_are_distinguished(self):
        self.run.update(event="pull_request", head_sha=HEAD)
        self.artifact["workflow_run"]["head_sha"] = HEAD
        self.commit["parents"].append({"sha": HEAD})
        receipt = self.verify()
        self.assertEqual(receipt["source_binding"], "verified-pr-merge-candidate")
        self.assertEqual(receipt["provider_head_sha"], HEAD)
        self.assertEqual(receipt["source_sha"], SOURCE)

    def test_unrelated_pr_merge_commit_is_rejected(self):
        self.run.update(event="pull_request", head_sha=HEAD)
        with self.assertRaisesRegex(ProvenanceError, "direct child"):
            verify_source_binding(SOURCE, self.run, self.commit)

    def test_pr_candidate_cannot_use_a_manifest_declaring_the_main_artifact_name(self):
        self.run.update(event="pull_request", head_sha=HEAD)
        self.artifact["workflow_run"]["head_sha"] = HEAD
        self.commit["parents"].append({"sha": HEAD})
        self.artifact["name"] = "pandora-mobile-android-candidates-" + SOURCE
        # This is the actual producer defect observed in the first native PR
        # run: the upload used candidates while its manifest said validation.
        with self.assertRaisesRegex(ProvenanceError, "Manifest artifact name differs"):
            self.verify("debug")
        self.fields["android_artifact_name"] = self.artifact["name"]
        self.write_manifest()
        receipt = self.verify("debug")
        self.assertEqual(receipt["artifact_name"], self.artifact["name"])
        self.assertEqual(receipt["source_sha"], SOURCE)
        self.assertEqual(receipt["provider_head_sha"], HEAD)
        self.assertEqual(receipt["apk_sha256"], self.fields["apk_sha256"])
        self.assertFalse(receipt["production_verified"])

    def test_push_cannot_substitute_another_source(self):
        self.run["head_sha"] = HEAD
        self.commit["parents"].append({"sha": HEAD})
        with self.assertRaisesRegex(ProvenanceError, "Non-PR"):
            verify_source_binding(SOURCE, self.run, self.commit)

    def test_wrong_repository_fork_failed_run_and_wrong_workflow_rejected(self):
        for patch in (
            {"repository": {"full_name": "unrelated/project"}},
            {"head_repository": {"full_name": "unrelated/project"}},
            {"conclusion": "failure"}, {"status": "in_progress"},
            {"path": ".github/workflows/unrelated.yml"},
        ):
            with self.subTest(patch=patch):
                run = {**self.run, **patch}
                with self.assertRaises(ProvenanceError):
                    verify_source_binding(SOURCE, run, self.commit)

    def test_artifact_metadata_cannot_replace_run_source_or_identity(self):
        for patch in (
            {"expired": True}, {"name": "pandora-mobile-android-validation-" + HEAD},
            {"workflow_run": {"id": 99, "head_sha": SOURCE}},
            {"workflow_run": {"id": 91, "head_sha": HEAD}},
        ):
            with self.subTest(patch=patch):
                artifact = {**self.artifact, **patch}
                with self.assertRaises(ProvenanceError):
                    verify_artifact(self.root, SOURCE, self.run, artifact, self.commit)

    def test_apk_changed_after_manifest_is_rejected(self):
        (self.root / "app-profile.apk").write_bytes(b"changed bytes")
        with self.assertRaisesRegex(ProvenanceError, "digest mismatch"):
            self.verify()

    def test_manifest_identity_class_and_size_mismatch_rejected(self):
        baseline = copy.deepcopy(self.fields)
        for key, value in (
            ("source_sha", HEAD), ("workflow_run_id", "99"),
            ("source_tree", HEAD), ("workflow_run_attempt", "2"),
            ("android_artifact_name", "wrong-artifact"),
            ("android_package", "com.unrelated.app"),
            ("production_release", "true"), ("artifact_class", "production"),
            ("profile_apk_size_bytes", "1"),
        ):
            with self.subTest(key=key):
                self.fields = {**baseline, key: value}
                self.write_manifest()
                with self.assertRaises(ProvenanceError):
                    self.verify()

    def test_duplicate_manifest_fields_and_duplicate_apks_rejected(self):
        self.manifest.write_text(self.manifest.read_text() + "source_sha=" + SOURCE + "\n")
        with self.assertRaisesRegex(ProvenanceError, "Duplicate"):
            read_manifest(self.manifest)
        self.write_manifest()
        other = self.root / "second"
        other.mkdir()
        (other / "app-profile.apk").write_bytes(self.profile)
        with self.assertRaisesRegex(ProvenanceError, "Exactly one"):
            self.verify()

    def archive(self, filename="app.apk", symlink=False):
        path = self.root / "archive.zip"
        with zipfile.ZipFile(path, "w") as zipped:
            item = zipfile.ZipInfo(filename)
            if symlink:
                item.external_attr = (stat.S_IFLNK | 0o777) << 16
            zipped.writestr(item, b"test-content")
        return path, hashlib.sha256(path.read_bytes()).hexdigest()

    def test_archive_must_match_provider_digest(self):
        archive, digest = self.archive()
        with self.assertRaisesRegex(ProvenanceError, "Archive digest mismatch"):
            extract_verified_archive(archive, self.root / "out", "f" * 64)
        extract_verified_archive(archive, self.root / "out", digest)
        self.assertEqual((self.root / "out/app.apk").read_bytes(), b"test-content")

    def test_archive_rejects_traversal_absolute_path_and_symlink(self):
        for index, (name, link) in enumerate((
            ("../outside.apk", False), ("/absolute.apk", False), ("link.apk", True)
        )):
            with self.subTest(name=name):
                archive, digest = self.archive(name, link)
                with self.assertRaises(ProvenanceError):
                    extract_verified_archive(archive, self.root / f"out{index}", digest)


if __name__ == "__main__":
    unittest.main()
