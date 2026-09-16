#!/usr/bin/env python3
"""M8-005 source-boundary tests for signed update and recovery trust."""

from __future__ import annotations

import unittest
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
_ANDROID = (
    _ROOT
    / "platform"
    / "android"
    / "app"
    / "src"
    / "main"
    / "kotlin"
    / "com"
    / "banataosystems"
    / "pandora_mobile"
)
_UPDATE = _ANDROID / "PandoraSignedUpdateChannel.kt"
_CHANNEL = _ANDROID / "PandoraDeviceAgentChannel.kt"
_DART = _ROOT / "lib" / "core" / "device" / "pandora_signed_update_channel.dart"
_WORKFLOW = _ROOT.parents[1] / ".github" / "workflows" / "pandora-mobile-integration.yml"


class SignedUpdateChannelContractTest(unittest.TestCase):
    def test_native_verifier_binds_signer_hash_version_and_source(self) -> None:
        source = _UPDATE.read_text(encoding="utf-8")
        for required in (
            "verifyManifestSignature",
            "installed_app_signer",
            "certificateSha256",
            "sha256File",
            "apkContainsSourceRevision",
            '"assets/flutter_assets/kernel_blob.bin"',
            "candidate.versionCode <= currentVersionCode",
            "recovery.versionCode <= candidate.versionCode",
            "exact_current_signer_v1",
        ):
            self.assertIn(required, source)

    def test_staging_and_install_boundaries_remain_fail_closed(self) -> None:
        source = _UPDATE.read_text(encoding="utf-8")
        for required in (
            "app_private_only",
            "forward_version_signed_recovery",
            '"requestInstallPackagesAllowed" to false',
            '"unknownSourcesInstallAllowed" to false',
            '"directInstallerExposed" to false',
            '"installExecuted" to false',
            '"physicalUpdateVerified" to false',
            '"physicalRollbackVerified" to false',
            "Production update verification is disabled on debuggable builds.",
        ):
            self.assertIn(required, source)
        for forbidden in (
            "PackageInstaller",
            "Runtime.getRuntime().exec",
            "ProcessBuilder",
            "ACTION_INSTALL_PACKAGE",
            "ACTION_VIEW",
        ):
            self.assertNotIn(forbidden, source)

    def test_device_agent_exposes_verify_not_install(self) -> None:
        source = _CHANNEL.read_text(encoding="utf-8")
        self.assertIn('"getSignedUpdatePolicy"', source)
        self.assertIn('"verifySignedUpdateBundle"', source)
        self.assertIn("PandoraSignedUpdateChannel(context)", source)
        for forbidden in (
            '"installSignedUpdate"',
            '"rollbackInstalledApk"',
            "PackageInstaller",
        ):
            self.assertNotIn(forbidden, source)

    def test_dart_contract_rejects_update_boundary_weakening(self) -> None:
        source = _DART.read_text(encoding="utf-8")
        for required in (
            "installed_app_signer",
            "apk_embedded_revision",
            "signed_manifest",
            "forward_version_signed_recovery",
            "requestInstallPackagesAllowed",
            "directInstallerExposed",
            "Signed update evidence must not carry credentials or secrets",
        ):
            self.assertIn(required, source)

    def test_existing_ci_keeps_unknown_source_permission_forbidden(self) -> None:
        source = _WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("REQUEST_INSTALL_PACKAGES", source)
        self.assertIn("Unexpected sensitive Android permission detected.", source)


if __name__ == "__main__":
    unittest.main()