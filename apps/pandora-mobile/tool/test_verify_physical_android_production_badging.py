import unittest
import verify_physical_android_candidate as verifier

class ProductionBadgingVerifierTest(unittest.TestCase):
    def test_accepts_non_debuggable_non_testonly_badging(self):
        verifier.require_production_badging(
            "package: name='com.banataosystems.pandora_mobile' versionCode='8' versionName='0.4.0-rc.2'\n"
            "application-label:'Pandora'\n"
        )

    def test_rejects_debuggable_badging(self):
        with self.assertRaisesRegex(verifier.VerificationError, "debuggable APK"):
            verifier.require_production_badging(
                "package: name='com.banataosystems.pandora_mobile' versionCode='8' versionName='0.4.0-rc.2'\n"
                "application-debuggable\n"
            )

    def test_rejects_testonly_badging(self):
        with self.assertRaisesRegex(verifier.VerificationError, "testOnly APK"):
            verifier.require_production_badging(
                "package: name='com.banataosystems.pandora_mobile' versionCode='8' versionName='0.4.0-rc.2'\n"
                "application-testOnly\n"
            )

if __name__ == "__main__":
    unittest.main()
