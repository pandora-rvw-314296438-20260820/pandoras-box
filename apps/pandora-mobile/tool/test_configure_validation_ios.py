import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("configure_validation_ios.py")
SPEC = importlib.util.spec_from_file_location("configure_validation_ios", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


SAMPLE = """// !$*UTF8*$!
{
objects = {
/* Begin PBXBuildFile section */
        AAA /* AppDelegate.swift in Sources */ = {isa = PBXBuildFile; fileRef = BBB /* AppDelegate.swift */; };
/* End PBXBuildFile section */
/* Begin PBXFileReference section */
        BBB /* AppDelegate.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppDelegate.swift; sourceTree = "<group>"; };
/* End PBXFileReference section */
/* Begin PBXGroup section */
        CCC /* Runner */ = {
            children = (
                BBB /* AppDelegate.swift */,
            );
        };
/* End PBXGroup section */
/* Begin PBXSourcesBuildPhase section */
        DDD /* Sources */ = {
            files = (
                AAA /* AppDelegate.swift in Sources */,
            );
        };
/* End PBXSourcesBuildPhase section */
};
}
"""


class ConfigureValidationIosTest(unittest.TestCase):
    def test_registers_exact_preview_source_idempotently(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory) / "project.pbxproj"
            project.write_text(SAMPLE, encoding="utf-8")

            MODULE.configure(project)
            once = project.read_text(encoding="utf-8")
            self.assertEqual(once.count(MODULE.FILE_REF), 3)
            self.assertEqual(once.count(MODULE.BUILD_REF), 2)
            self.assertIn(
                f"{MODULE.FILE_NAME} in Sources",
                once,
            )

            MODULE.configure(project)
            self.assertEqual(project.read_text(encoding="utf-8"), once)

    def test_rejects_unexpected_project_structure(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory) / "project.pbxproj"
            project.write_text("not an xcode project", encoding="utf-8")
            with self.assertRaises(SystemExit):
                MODULE.configure(project)


if __name__ == "__main__":
    unittest.main()
