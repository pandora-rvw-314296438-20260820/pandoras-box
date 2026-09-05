import unittest

import verify_physical_android_candidate as verifier


class ProductionSignatureSchemeVerifierTest(unittest.TestCase):
    def test_accepts_v2_verified(self):
        verifier.require_modern_signature_scheme(
            "Verified using v1 scheme (JAR signing): true\n"
            "Verified using v2 scheme (APK Signature Scheme v2): true\n"
            "Verified using v3 scheme (APK Signature Scheme v3): false\n"
        )

    def test_accepts_v3_verified(self):
        verifier.require_modern_signature_scheme(
            "Verified using v1 scheme (JAR signing): false\n"
            "Verified using v2 scheme (APK Signature Scheme v2): false\n"
            "Verified using v3 scheme (APK Signature Scheme v3): true\n"
        )

    def test_rejects_v1_only(self):
        with self.assertRaisesRegex(verifier.VerificationError, "requires APK Signature Scheme v2 or v3"):
            verifier.require_modern_signature_scheme(
                "Verified using v1 scheme (JAR signing): true\n"
                "Verified using v2 scheme (APK Signature Scheme v2): false\n"
                "Verified using v3 scheme (APK Signature Scheme v3): false\n"
            )

    def test_rejects_missing_modern_scheme_evidence(self):
        with self.assertRaisesRegex(verifier.VerificationError, "missing v2/v3"):
            verifier.require_modern_signature_scheme("Verified using v1 scheme (JAR signing): true\n")


if __name__ == "__main__":
    unittest.main()
