package com.banataosystems.pandora.uicapture;

import android.app.Activity;
import android.app.Instrumentation;
import android.app.UiAutomation;
import android.graphics.Rect;
import android.os.Bundle;
import android.os.SystemClock;
import android.util.Base64;
import android.view.accessibility.AccessibilityNodeInfo;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/** CI-only observation. Does not launch, focus, click, type, or authenticate. */
public final class CaptureInstrumentation extends Instrumentation {
  private Bundle arguments;
  private int visited;

  @Override public void onCreate(Bundle args) {
    super.onCreate(args);
    arguments = args;
    start();
  }

  @Override public void onStart() {
    if (arguments == null || !CaptureXml.TARGET_PACKAGE.equals(arguments.getString("target_package"))) {
      fail("TARGET_NOT_ALLOWED");
      return;
    }
    try {
      UiAutomation automation = getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES);
      long deadline = SystemClock.uptimeMillis() + 5000;
      boolean sawTarget = false;
      while (SystemClock.uptimeMillis() < deadline) {
        AccessibilityNodeInfo root = automation.getRootInActiveWindow();
        if (root != null) {
          List<CaptureXml.Node> nodes = new ArrayList<>();
          visited = 0;
          try { collect(root, nodes, 0); } finally { root.recycle(); }
          sawTarget |= !nodes.isEmpty();
          if (CaptureXml.hasFieldSemantics(nodes)) {
            String xml = CaptureXml.encode(nodes);
            Bundle result = new Bundle();
            result.putString("status", "ok");
            result.putString("capture_schema", CaptureXml.SCHEMA);
            result.putInt("node_count", nodes.size());
            result.putString("capture_base64", Base64.encodeToString(xml.getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP));
            finish(Activity.RESULT_OK, result);
            return;
          }
        }
        SystemClock.sleep(100);
      }
      fail(sawTarget ? "SEMANTICS_NOT_READY" : "TARGET_NOT_VISIBLE");
    } catch (IllegalArgumentException boundedFailure) {
      String code = boundedFailure.getMessage();
      fail("NODE_LIMIT".equals(code) || "DEPTH_LIMIT".equals(code) || "LABEL_LIMIT".equals(code)
          || "CAPTURE_LIMIT".equals(code) ? code : "CAPTURE_UNAVAILABLE");
    } catch (Exception unavailable) {
      // Never emit exception text, device contents, paths or a stack trace.
      fail("CAPTURE_UNAVAILABLE");
    }
  }

  private void collect(AccessibilityNodeInfo node, List<CaptureXml.Node> output, int depth) {
    if (++visited > CaptureXml.MAX_NODES) throw new IllegalArgumentException("NODE_LIMIT");
    if (depth > 32) throw new IllegalArgumentException("DEPTH_LIMIT");
    if (CaptureXml.TARGET_PACKAGE.equals(string(node.getPackageName())) && node.isVisibleToUser()) {
      CaptureXml.Node item = new CaptureXml.Node();
      item.packageName = CaptureXml.TARGET_PACKAGE;
      item.className = string(node.getClassName());
      item.text = string(node.getText());
      item.description = string(node.getContentDescription());
      item.hint = string(node.getHintText());
      item.enabled = node.isEnabled();
      item.clickable = node.isClickable();
      item.password = node.isPassword();
      item.editable = node.isEditable();
      Rect bounds = new Rect();
      node.getBoundsInScreen(bounds);
      item.left = bounds.left; item.top = bounds.top; item.right = bounds.right; item.bottom = bounds.bottom;
      output.add(item);
    }
    for (int i = 0; i < node.getChildCount(); i++) {
      AccessibilityNodeInfo child = node.getChild(i);
      if (child == null) continue;
      try { collect(child, output, depth + 1); } finally { child.recycle(); }
    }
  }

  private static String string(CharSequence value) { return value == null ? "" : value.toString(); }

  private void fail(String code) {
    Bundle result = new Bundle();
    result.putString("status", "error");
    result.putString("capture_schema", CaptureXml.SCHEMA);
    result.putString("error_code", code);
    finish(Activity.RESULT_CANCELED, result);
  }
}
