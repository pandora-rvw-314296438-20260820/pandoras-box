package com.banataosystems.pandora.uicapture;

import java.util.ArrayList;
import java.util.List;

/** Bounded, package-restricted serialization; never serializes editable values. */
public final class CaptureXml {
  public static final String TARGET_PACKAGE = "com.banataosystems.pandora.plp";
  public static final String SCHEMA = "pandora.android.ui-capture.v1";
  public static final int MAX_NODES = 512;
  private static final int MAX_XML_CHARS = 131072;
  private static final int MAX_LABEL_CHARS = 2048;

  public static final class Node {
    public String packageName = "", className = "", text = "", description = "", hint = "";
    public int left, top, right, bottom;
    public boolean enabled, clickable, password, editable;

    public boolean isInput() {
      return editable || password || className.endsWith("EditText");
    }
  }

  /** Flutter may initially expose only its native frame as automation connects. */
  public static boolean hasFieldSemantics(List<Node> nodes) {
    boolean fieldHint = false;
    boolean noninputLabel = false;
    for (Node node : nodes) {
      if (!TARGET_PACKAGE.equals(node.packageName)) continue;
      if (node.isInput() && !node.hint.isEmpty()) fieldHint = true;
      if (!node.isInput() && (!node.text.isEmpty() || !node.description.isEmpty())) {
        noninputLabel = true;
      }
    }
    // Readiness never manufactures or validates expected label text. The caller
    // must still assert exact native field labels, errors, flags and bounds.
    return fieldHint && noninputLabel;
  }

  public static String encode(List<Node> nodes) {
    if (nodes.size() > MAX_NODES) throw new IllegalArgumentException("NODE_LIMIT");
    // A label elsewhere in the same window must not echo an entered value.
    List<String> inputValues = new ArrayList<>();
    for (Node node : nodes) {
      if (TARGET_PACKAGE.equals(node.packageName) && node.isInput() && !node.text.isEmpty()) {
        inputValues.add(node.text);
      }
    }
    StringBuilder xml = new StringBuilder("<?xml version=\"1.0\" encoding=\"UTF-8\"?><hierarchy schema=\"");
    xml.append(SCHEMA).append("\">");
    int index = 0;
    for (Node node : nodes) {
      if (!TARGET_PACKAGE.equals(node.packageName)) continue;
      boolean input = node.isInput();
      xml.append("<node index=\"").append(index++).append('"');
      attr(xml, "package", node.packageName);
      attr(xml, "class", node.className);
      attr(xml, "text", input ? "" : redact(node.text, inputValues));
      attr(xml, "content-desc", input ? "" : redact(node.description, inputValues));
      // Android maps Flutter field labels and validation messages to hintText.
      attr(xml, "hint", redact(node.hint, inputValues));
      attr(xml, "bounds", "[" + node.left + "," + node.top + "][" + node.right + "," + node.bottom + "]");
      attr(xml, "enabled", Boolean.toString(node.enabled));
      attr(xml, "clickable", Boolean.toString(node.clickable));
      attr(xml, "password", Boolean.toString(node.password));
      attr(xml, "editable", Boolean.toString(node.editable));
      attr(xml, "input-value-redacted", Boolean.toString(input));
      xml.append("/>");
      if (xml.length() > MAX_XML_CHARS) throw new IllegalArgumentException("CAPTURE_LIMIT");
    }
    xml.append("</hierarchy>");
    return xml.toString();
  }

  private static String redact(String value, List<String> inputValues) {
    String safe = value;
    for (String input : inputValues) safe = safe.replace(input, "[redacted]");
    return safe;
  }

  private static void attr(StringBuilder xml, String name, String value) {
    if (value.length() > MAX_LABEL_CHARS) throw new IllegalArgumentException("LABEL_LIMIT");
    xml.append(' ').append(name).append("=\"");
    for (int i = 0; i < value.length(); i++) {
      char ch = value.charAt(i);
      switch (ch) {
        case '&': xml.append("&amp;"); break;
        case '<': xml.append("&lt;"); break;
        case '>': xml.append("&gt;"); break;
        case '"': xml.append("&quot;"); break;
        case '\'': xml.append("&apos;"); break;
        case '\n': xml.append("&#10;"); break;
        case '\r': xml.append("&#13;"); break;
        case '\t': xml.append("&#9;"); break;
        default: xml.append(ch >= 0x20 && ch != 0xFFFE && ch != 0xFFFF ? ch : '\uFFFD');
      }
    }
    xml.append('"');
  }

  private CaptureXml() {}
}
