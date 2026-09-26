import unittest
from pathlib import Path


_APP = Path(__file__).resolve().parents[1]


class EurofishEnterpriseIsolationTest(unittest.TestCase):
    def test_dedicated_entrypoint_isolated_to_eurofish_shell(self):
        entry = (_APP / "lib" / "main_eurofish.dart").read_text()
        app = (_APP / "lib" / "app" / "eurofish_enterprise_app.dart").read_text()
        auth = (_APP / "lib" / "features" / "auth" / "eurofish_auth_gate.dart").read_text()
        shell = (_APP / "lib" / "app" / "eurofish_enterprise_shell.dart").read_text()
        combined = "\n".join([entry, app, auth, shell])

        self.assertIn("EurofishEnterpriseApp", entry)
        self.assertIn("EurofishEnterpriseShell", auth)
        self.assertIn("1064-euro-fish-traders", shell)
        self.assertIn("assets/workspaces/eurofish.webp", shell)
        self.assertIn("allowCharacterContext: false", shell)
        self.assertIn("allowProjectContext: false", shell)
        self.assertNotIn("PlpEnterpriseShell", combined)
        self.assertNotIn("EnterpriseWorkspaceHome(", shell)

    def test_current_import_export_navigation_is_present(self):
        shell = (_APP / "lib" / "features" / "enterprise" / "enterprise_workspace_home.dart").read_text()
        start = shell.index("key: '1064-euro-fish-traders'")
        end = shell.index("key: 'batalla-associates'", start)
        eurofish = shell[start:end]
        expected = [
            "Home",
            "Overview",
            "Tax & Compliance",
            "Orders & Shipments",
            "Suppliers & Buyers",
            "Inventory & Products",
            "Logistics & Customs",
            "Sales & Finance",
            "Documents & Compliance",
            "Team & Access",
            "Activity",
            "Settings",
            "System / Developer",
        ]
        positions = [eurofish.index("'" + label + "'") for label in expected]
        self.assertEqual(positions, sorted(positions))


if __name__ == "__main__":
    unittest.main()
