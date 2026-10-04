import unittest
from core_resolve_mobile_build import matching_artifact, matching_runs
from core_artifact_provenance import CANONICAL_REPOSITORY, MOBILE_WORKFLOW


class BuildResolutionTest(unittest.TestCase):
    def test_provider_head_alone_cannot_select_another_merge_artifact(self):
        source = "a" * 40
        artifact = {"id": 1, "name": "pandora-mobile-android-validation-" + "b" * 40,
                    "expired": False}
        self.assertIsNone(matching_artifact([artifact], source))
        artifact["name"] = "pandora-mobile-android-validation-" + source
        self.assertIs(matching_artifact([artifact], source), artifact)

    def test_expired_and_ambiguous_candidates_are_rejected(self):
        artifact = {"id": 1, "name": "pandora-mobile-android-validation-" + "a" * 40,
                    "expired": True}
        self.assertIsNone(matching_artifact([artifact], "a" * 40))
        artifact["expired"] = False
        with self.assertRaisesRegex(RuntimeError, "AMBIGUOUS"):
            matching_artifact([artifact, {**artifact, "id": 2}], "a" * 40)

    def test_resolver_only_considers_same_repository_mobile_pr_runs(self):
        run = {"id": 10, "head_sha": "b" * 40, "event": "pull_request",
               "path": MOBILE_WORKFLOW, "head_repository": {"full_name": CANONICAL_REPOSITORY}}
        values = [run, {**run, "id": 11, "path": "other.yml"},
                  {**run, "id": 12, "head_repository": {"full_name": "fork/repo"}},
                  {**run, "id": 13, "head_sha": "c" * 40}]
        self.assertEqual(matching_runs(values, "b" * 40), [run])


if __name__ == "__main__":
    unittest.main()
