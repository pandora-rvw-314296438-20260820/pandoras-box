#!/usr/bin/env python3
"""Static compile-surface guard for the dedicated PLP Flutter target."""

from __future__ import annotations

import unittest
from pathlib import Path

_APP = Path(__file__).resolve().parents[1]
_FILES = [
    _APP / "lib" / "main_plp.dart",
    _APP / "lib" / "app" / "plp_enterprise_app.dart",
    _APP / "lib" / "app" / "plp_enterprise_shell.dart",
    _APP / "lib" / "features" / "auth" / "plp_auth_gate.dart",
]


class PlpEnterpriseIsolationTest(unittest.TestCase):
    def test_dedicated_target_has_no_generic_workspace_or_auth_fallback(self) -> None:
        combined = "\n".join(path.read_text(encoding="utf-8") for path in _FILES)

        for forbidden in (
            "PANDORA_ENTERPRISE_WORKSPACE",
            "enterprise_workspace_home.dart",
            "EnterpriseWorkspaceHome",
            "import 'pandora_app.dart';",
            "features/auth/auth_gate.dart",
            "PandoraShell",
            "PandoraChatShell",
            "Owners workspace",
            "Euro-Fish",
            "Batalla",
            "BOK",
            "Melodee",
        ):
            self.assertNotIn(forbidden, combined)

        self.assertIn("PlpEnterpriseApp", combined)
        self.assertIn("PlpAuthGate", combined)
        self.assertIn("PlpEnterpriseShell", combined)
        self.assertIn("plp_enterprise_mobile_bootstrap_v1", combined)
        self.assertIn("allowCharacterContext: false", combined)
        self.assertIn("allowProjectContext: false", combined)
        self.assertIn("label: 'Home'", combined)
        self.assertIn("label: 'Alfred'", combined)
        self.assertIn("label: 'Operations'", combined)
        self.assertIn("label: 'Vision'", combined)
        self.assertIn("label: 'Local AI'", combined)


if __name__ == "__main__":
    unittest.main()
