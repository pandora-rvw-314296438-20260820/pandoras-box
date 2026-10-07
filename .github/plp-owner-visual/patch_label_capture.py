#!/usr/bin/env python3
"""Inspector-only label mode. Sign-in readiness behavior stays unchanged."""
import sys
from pathlib import Path

root = Path(sys.argv[1])
xml_path = root / "src/com/banataosystems/pandora/uicapture/CaptureXml.java"
inst_path = root / "src/com/banataosystems/pandora/uicapture/CaptureInstrumentation.java"
xml_text = xml_path.read_text()
if "hasLabelSemantics" not in xml_text:
    needle = "  public static boolean hasFieldSemantics"
    if needle not in xml_text:
        raise SystemExit("CaptureXml insertion point missing")
    xml_text = xml_text.replace(
        needle,
        """  public static boolean hasLabelSemantics(List<Node> nodes) {
    for (Node node : nodes) {
      if (!TARGET_PACKAGE.equals(node.packageName) || node.isInput()) continue;
      if (!node.text.isEmpty() || !node.description.isEmpty()) return true;
    }
    return false;
  }

"""
        + needle,
        1,
    )
    xml_path.write_text(xml_text)

inst_text = inst_path.read_text()
old = "if (CaptureXml.hasFieldSemantics(nodes)) {"
new = (
    'boolean labelsOnly = "labels".equals(arguments.getString("capture_mode"));\n'
    "          if ((labelsOnly && CaptureXml.hasLabelSemantics(nodes)) "
    "|| (!labelsOnly && CaptureXml.hasFieldSemantics(nodes))) {"
)
if "labelsOnly" not in inst_text:
    if old not in inst_text:
        raise SystemExit("instrumentation insertion point missing")
    inst_path.write_text(inst_text.replace(old, new, 1))
print("inspector label mode enabled")
