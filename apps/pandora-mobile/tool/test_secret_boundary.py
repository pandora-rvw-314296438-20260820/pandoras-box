import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).with_name("check_secret_boundary.py")
_SPEC = importlib.util.spec_from_file_location("check_secret_boundary", _SCRIPT)
assert _SPEC and _SPEC.loader
scanner = importlib.util.module_from_spec(_SPEC)
sys.modules[_SPEC.name] = scanner
_SPEC.loader.exec_module(scanner)


class SecretBoundaryScannerTest(unittest.TestCase):
    def test_publishable_client_material_is_allowed(self):
        source = (
            b"PANDORA_SUPABASE_PUBLISHABLE_KEY=sb_publishable_example_public_value\n"
            b"--dart-define=PANDORA_SUPABASE_PUBLISHABLE_KEY=sb_publishable_example\n"
        )
        self.assertEqual(scanner.scan_bytes(source, location="safe.txt"), [])

    def test_forbidden_provider_identifier_fails_without_echoing_value(self):
        secret_value = "github_pat_" + ("A" * 40)
        source = f"GITHUB_PAT={secret_value}\n".encode()
        findings = scanner.scan_bytes(source, location="unsafe.env")
        rendered = scanner.render_findings(findings)
        self.assertIn("forbidden_provider_secret_identifier", rendered)
        self.assertIn("github_pat_literal", rendered)
        self.assertNotIn(secret_value, rendered)

    def test_actions_secret_injection_is_forbidden(self):
        source = b"token: ${{ secrets.PANDORA_MOBILE_BUILD_TOKEN }}\n"
        findings = scanner.scan_bytes(source, location="workflow.yml")
        self.assertTrue(
            any(item.rule == "github_actions_secret_injection" for item in findings)
        )

    def test_sensitive_dart_define_is_forbidden(self):
        source = b"--dart-define=PANDORA_OPENAI_API_KEY=synthetic\n"
        findings = scanner.scan_bytes(source, location="workflow.yml")
        self.assertTrue(any(item.rule == "sensitive_dart_define" for item in findings))

    def test_cli_reports_fingerprint_not_plaintext(self):
        secret_value = "sk-" + ("Z" * 32)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "source.dart"
            path.write_text(f"const value = '{secret_value}';\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(_SCRIPT), str(path)],
                text=True,
                capture_output=True,
                check=False,
            )
        self.assertEqual(result.returncode, 1)
        self.assertIn("fingerprint=", result.stderr)
        self.assertNotIn(secret_value, result.stderr)

    def test_current_mobile_operational_sources_pass_secret_boundary(self):
        repo_root = Path(__file__).resolve().parents[3]
        targets = [
            repo_root / "apps" / "pandora-mobile" / "lib",
            repo_root / "apps" / "pandora-mobile" / "platform",
            repo_root / "apps" / "pandora-mobile" / "pubspec.yaml",
            repo_root / "apps" / "pandora-mobile" / "pubspec.lock",
            repo_root / ".github" / "workflows" / "pandora-mobile-integration.yml",
        ]
        self.assertTrue(all(path.exists() for path in targets))
        self.assertEqual(scanner.scan_source_targets(targets), [])


if __name__ == "__main__":
    unittest.main()
