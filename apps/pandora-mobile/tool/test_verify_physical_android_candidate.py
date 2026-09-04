import hashlib
import tempfile
import unittest
from pathlib import Path
import verify_physical_android_candidate as verifier
class PhysicalAndroidCandidateVerifierTest(unittest.TestCase):
    def test_manifest_binding_requires_external_gates_to_remain_false(self):
        with tempfile.TemporaryDirectory() as tmp:
            apk=Path(tmp)/"candidate.apk"; apk.write_bytes(b"pandora"); digest=hashlib.sha256(b"pandora").hexdigest()
            manifest={"source_sha":"a"*40,"apk_sha256":digest,"android_package":verifier.EXPECTED_PACKAGE,"app_version":"0.4.0-rc.2+8","artifact_class":"validation-candidate","production_release":"false","physical_device_verified":"false","wifi_journey_verified":"false","mobile_data_journey_verified":"false","authenticated_owner_journey_verified":"false","rollback_verified":"false"}
            verifier.require_manifest_binding(manifest,source_sha="a"*40,apk_sha256=digest,package_name=verifier.EXPECTED_PACKAGE,app_version="0.4.0-rc.2+8")
            manifest["physical_device_verified"]="true"
            with self.assertRaisesRegex(verifier.VerificationError,"physical_device_verified=false"):
                verifier.require_manifest_binding(manifest,source_sha="a"*40,apk_sha256=digest,package_name=verifier.EXPECTED_PACKAGE,app_version="0.4.0-rc.2+8")
    def test_parse_manifest_rejects_duplicate_keys(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"manifest.txt"; path.write_text("source_sha=a\nsource_sha=b\n",encoding="utf-8")
            with self.assertRaisesRegex(verifier.VerificationError,"duplicate"): verifier.parse_manifest(path)
    def test_badging_parser_binds_package_and_version(self):
        package,version_name,version_code=verifier.parse_badging("package: name='com.banataosystems.pandora_mobile' versionCode='8' versionName='0.4.0-rc.2'")
        self.assertEqual(package,verifier.EXPECTED_PACKAGE); self.assertEqual(version_name,"0.4.0-rc.2"); self.assertEqual(version_code,"8")
    def test_production_signer_detector_is_fail_closed_for_android_debug(self):
        self.assertTrue(verifier.signer_is_debug("Signer #1 certificate DN: CN=Android Debug,O=Android,C=US"))
        self.assertFalse(verifier.signer_is_debug("Signer #1 certificate DN: CN=Pandora Release,O=Banatao Systems"))
if __name__=="__main__": unittest.main()
