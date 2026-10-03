import com.banataosystems.pandora.uicapture.CaptureXml;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import javax.xml.parsers.DocumentBuilderFactory;
import org.w3c.dom.Document;
import org.w3c.dom.Element;

public final class CaptureXmlTest {
  private static CaptureXml.Node node(String className, String text) {
    CaptureXml.Node result = new CaptureXml.Node();
    result.packageName = CaptureXml.TARGET_PACKAGE;
    result.className = className;
    result.text = text;
    result.enabled = true;
    result.clickable = true;
    result.left = 12; result.top = 34; result.right = 210; result.bottom = 89;
    return result;
  }

  private static void check(boolean condition, String message) {
    if (!condition) throw new AssertionError(message);
  }

  private static Document parse(String xml) throws Exception {
    return DocumentBuilderFactory.newInstance().newDocumentBuilder()
        .parse(new ByteArrayInputStream(xml.getBytes(StandardCharsets.UTF_8)));
  }

  public static void main(String[] args) throws Exception {
    CaptureXml.Node email = node("android.widget.EditText", "entered-email-value");
    email.hint = "Email, Enter your email.";
    email.description = "entered-email-value";
    CaptureXml.Node hidden = node("android.widget.EditText", "hidden-entry-value");
    hidden.password = true;
    hidden.hint = "Password, Enter your password.";
    CaptureXml.Node visible = node("android.widget.EditText", "visible-entry-value");
    visible.password = false;
    visible.hint = "Password";
    CaptureXml.Node custom = node("custom.Input", "custom-entry-value");
    custom.editable = true;
    custom.hint = "Custom custom-entry-value";
    CaptureXml.Node button = node("android.widget.Button", "");
    button.description = "Sign in";
    CaptureXml.Node mirrored = node("android.view.View", "Error for visible-entry-value");
    CaptureXml.Node foreign = node("android.view.View", "foreign-app-label");
    foreign.packageName = CaptureXml.TARGET_PACKAGE + ".lookalike";
    check(!CaptureXml.hasFieldSemantics(Arrays.asList(node("android.widget.FrameLayout", ""))),
        "A native frame is not Flutter sign-in semantics readiness");
    check(!CaptureXml.hasFieldSemantics(Arrays.asList(button)), "Labels alone are not field readiness");
    check(CaptureXml.hasFieldSemantics(Arrays.asList(email, button)), "Actual field metadata becomes ready");
    CaptureXml.Node wrongHint = node("android.widget.EditText", "");
    wrongHint.hint = "Wrong label";
    check(CaptureXml.hasFieldSemantics(Arrays.asList(wrongHint, button)),
        "Readiness must leave exact-label failures to the caller, never hide or replace wrong labels");
    String xml = CaptureXml.encode(Arrays.asList(email, hidden, visible, custom, button, mirrored, foreign));
    Document document = parse(xml);
    check(document.getElementsByTagName("node").getLength() == 6, "Only the exact target package is serialized");
    for (String value : Arrays.asList("entered-email-value", "hidden-entry-value", "visible-entry-value", "custom-entry-value", "foreign-app-label")) {
      check(!xml.contains(value), "Input values and foreign labels must never be emitted");
    }
    for (int i = 0; i < 4; i++) {
      Element field = (Element) document.getElementsByTagName("node").item(i);
      check(field.getAttribute("text").isEmpty(), "Every editable value is redacted");
      check(field.getAttribute("content-desc").isEmpty(), "Input descriptions cannot echo values");
      check("true".equals(field.getAttribute("input-value-redacted")), "Redaction is explicit");
    }
    Element emailNode = (Element) document.getElementsByTagName("node").item(0);
    check("Email, Enter your email.".equals(emailNode.getAttribute("hint")), "Native field label and validation hint remain exact");
    Element passwordNode = (Element) document.getElementsByTagName("node").item(1);
    check("true".equals(passwordNode.getAttribute("password")), "Obscuring flag remains native evidence");
    Element signIn = (Element) document.getElementsByTagName("node").item(4);
    check("Sign in".equals(signIn.getAttribute("content-desc")), "Noninput button label is retained");
    check("[12,34][210,89]".equals(signIn.getAttribute("bounds")), "Actual bounds are retained");

    CaptureXml.Node escaped = node("android.view.View", "A & B < C > D \"quoted\" 'single'\nline");
    Element escapedNode = (Element) parse(CaptureXml.encode(Arrays.asList(escaped))).getElementsByTagName("node").item(0);
    check(escaped.text.equals(escapedNode.getAttribute("text")), "XML escaping preserves labels exactly");
    List<CaptureXml.Node> tooMany = new ArrayList<>();
    for (int i = 0; i <= CaptureXml.MAX_NODES; i++) tooMany.add(button);
    try { CaptureXml.encode(tooMany); throw new AssertionError("Node bound must fail closed"); }
    catch (IllegalArgumentException expected) { check("NODE_LIMIT".equals(expected.getMessage()), "Bounded public code"); }
    CaptureXml.Node tooLong = node("android.view.View", new String(new char[2049]).replace('\0', 'x'));
    try { CaptureXml.encode(Arrays.asList(tooLong)); throw new AssertionError("Label bound must fail closed"); }
    catch (IllegalArgumentException expected) { check("LABEL_LIMIT".equals(expected.getMessage()), "Bounded public code"); }
    System.out.println("CaptureXmlTest: native readiness, package isolation, all input redaction, native hints, bounds, XML escaping and limits PASS");
  }
}
