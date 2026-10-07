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
    inst_text = inst_text.replace(old, new, 1)
if "applyRequestedText" not in inst_text:
    call = "          try { collect(root, nodes, 0); } finally { root.recycle(); }"
    if call not in inst_text:
        raise SystemExit("collect insertion point missing")
    inst_text = inst_text.replace(
        call,
        "          applyRequestedText(root);\n" + call,
        1,
    )
    method = '''
  private boolean textApplied;

  private void applyRequestedText(AccessibilityNodeInfo node) {
    if (textApplied || node == null) return;
    String hintWanted = arguments.getString("set_text_hint");
    String encoded = arguments.getString("set_text_b64");
    if (hintWanted == null || hintWanted.isEmpty() || encoded == null || encoded.isEmpty()) return;
    if (node.isEditable()) {
      String hint = string(node.getHintText());
      if (hint.startsWith(hintWanted)) {
        String value = new String(Base64.decode(encoded, Base64.DEFAULT), StandardCharsets.UTF_8);
        Bundle args = new Bundle();
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, value);
        node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args);
        textApplied = true;
        SystemClock.sleep(300);
        return;
      }
    }
    for (int i = 0; i < node.getChildCount() && !textApplied; i++) {
      AccessibilityNodeInfo child = node.getChild(i);
      if (child == null) continue;
      try { applyRequestedText(child); } finally { child.recycle(); }
    }
  }

'''
    marker = "  private void collect("
    if marker not in inst_text:
        raise SystemExit("method insertion point missing")
    inst_text = inst_text.replace(marker, method + marker, 1)
if 'result.putString("text_applied"' not in inst_text:
    inst_text = inst_text.replace(
        'result.putString("status", "ok");',
        'result.putString("status", "ok");\n'
        '            result.putString("text_applied", textApplied ? "true" : "false");',
        1,
    )
inst_path.write_text(inst_text)
print("inspector label mode enabled")

