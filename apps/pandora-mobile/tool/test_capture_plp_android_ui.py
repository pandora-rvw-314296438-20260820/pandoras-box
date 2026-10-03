import base64
import importlib.util
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

SPEC = importlib.util.spec_from_file_location(
    "capture_plp_android_ui", Path(__file__).with_name("capture_plp_android_ui.py"))
capture = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(capture)


def fixture(validation=False):
    root = ET.Element("hierarchy", schema=capture.SCHEMA)
    for label in ("Email", "Password"):
        hint = label + ("\nEnter your " + label.lower() + "." if validation else "")
        ET.SubElement(root, "node", {
            "package": capture.PACKAGE, "class": "android.widget.EditText",
            "text": "", "content-desc": "", "hint": hint, "editable": "true",
            "password": str(label == "Password").lower(), "enabled": "true",
            "input-value-redacted": "true", "bounds": "[20,100][300,160]",
        })
    ET.SubElement(root, "node", {
        "package": capture.PACKAGE, "class": "android.widget.Button",
        "text": "", "content-desc": "Sign in", "hint": "",
        "clickable": "true", "enabled": "true", "password": "false",
        "editable": "false", "bounds": "[20,200][300,260]",
    })
    return root


def result(root, status="ok", code="-1"):
    encoded = base64.b64encode(ET.tostring(root)).decode("ascii")
    return (f"INSTRUMENTATION_RESULT: status={status}\n"
            f"INSTRUMENTATION_RESULT: capture_schema={capture.SCHEMA}\n"
            f"INSTRUMENTATION_RESULT: node_count={len(root)}\n"
            f"INSTRUMENTATION_RESULT: capture_base64={encoded}\n"
            f"INSTRUMENTATION_CODE: {code}\n")


class NativeCaptureTests(unittest.TestCase):
    def test_native_hints_and_content_description_button_are_tappable(self):
        _, nodes = capture.decode_capture(result(fixture()))
        self.assertEqual(capture.verify_sign_in(nodes, "sign-in"), (160, 230))
        self.assertEqual(capture.verify_sign_in(nodes, "restart"), (160, 230))

    def test_empty_validation_must_belong_to_each_native_input(self):
        _, nodes = capture.decode_capture(result(fixture(validation=True)))
        self.assertEqual(capture.verify_sign_in(nodes, "validation"), (160, 230))
        nodes[0].set("hint", "Email")
        nodes[2].set("text", "Enter your email.")
        with self.assertRaisesRegex(capture.CaptureFailure, "VALIDATION_MISSING"):
            capture.verify_sign_in(nodes, "validation")

    def test_empty_or_unobscured_fields_cannot_pass(self):
        for change in (lambda r: r[0].set("hint", ""),
                       lambda r: r[1].set("password", "false"),
                       lambda r: r[2].set("clickable", "false"),
                       lambda r: r[2].set("bounds", "[0,0][0,0]")):
            root = fixture()
            change(root)
            _, nodes = capture.decode_capture(result(root))
            with self.assertRaises(capture.CaptureFailure):
                capture.verify_sign_in(nodes, "sign-in")

    def test_failure_missing_schema_and_duplicate_success_are_denied(self):
        good = result(fixture())
        for bad in (result(fixture(), status="error"), result(fixture(), code="0"),
                    good.replace(capture.SCHEMA, "wrong"),
                    good + "INSTRUMENTATION_RESULT: status=ok\n"):
            with self.assertRaises(capture.CaptureFailure):
                capture.decode_capture(bad)

    def test_other_packages_and_input_values_never_reach_evidence(self):
        for change in (lambda r: r[0].set("package", "other.package"),
                       lambda r: r[0].set("text", "fixture-input"),
                       lambda r: r[1].set("content-desc", "fixture-password"),
                       lambda r: r[0].set("input-value-redacted", "false")):
            root = fixture()
            change(root)
            with self.assertRaises(capture.CaptureFailure):
                capture.decode_capture(result(root))


if __name__ == "__main__":
    unittest.main()
