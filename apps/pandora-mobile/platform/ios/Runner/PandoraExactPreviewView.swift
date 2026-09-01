import Flutter
import UIKit
import WebKit

private let pandoraPreviewScheme = "pandora-preview"
private let pandoraPreviewHost = "local"
private let pandoraPreviewMaxFileCount = 1000
private let pandoraPreviewMaxFileBytes = 10 * 1024 * 1024
private let pandoraPreviewMaxBundleBytes = 12 * 1024 * 1024

private struct PandoraPreviewFile {
    let data: Data
    let mimeType: String
}

private struct PandoraPreviewBundle {
    let versionId: String
    let files: [String: PandoraPreviewFile]

    static func parse(_ arguments: Any?) -> PandoraPreviewBundle? {
        guard
            let params = arguments as? [String: Any],
            let rawVersion = params["versionId"] as? String
        else { return nil }
        let versionId = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !versionId.isEmpty else { return nil }

        guard let rawFiles = params["files"] as? [[String: Any]],
              !rawFiles.isEmpty,
              rawFiles.count <= pandoraPreviewMaxFileCount
        else { return nil }

        var files: [String: PandoraPreviewFile] = [:]
        var totalBytes = 0
        for raw in rawFiles {
            guard
                let rawPath = raw["file"] as? String,
                let rawMime = raw["mimeType"] as? String,
                let rawBase64 = raw["dataBase64"] as? String
            else { return nil }
            let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let mimeType = rawMime.trimmingCharacters(in: .whitespacesAndNewlines)
            let dataBase64 = rawBase64.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isSafePreviewPath(path),
                  !mimeType.isEmpty,
                  !dataBase64.isEmpty,
                  files[path] == nil,
                  let data = Data(base64Encoded: dataBase64),
                  data.count <= pandoraPreviewMaxFileBytes
            else { return nil }
            totalBytes += data.count
            guard totalBytes <= pandoraPreviewMaxBundleBytes else { return nil }
            files[path] = PandoraPreviewFile(data: data, mimeType: mimeType)
        }
        guard files["index.html"] != nil else { return nil }
        return PandoraPreviewBundle(versionId: versionId, files: files)
    }

    private static func isSafePreviewPath(_ path: String) -> Bool {
        if path.isEmpty || path.count > 512 || path.hasPrefix("/") || path.hasSuffix("/") ||
            path.contains("\\") || path.contains("\0") || path.contains("?") || path.contains("#") {
            return false
        }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { part in
            !part.isEmpty && part != "." && part != ".." && part.count <= 255
        }
    }
}

private final class PandoraPreviewSchemeHandler: NSObject, WKURLSchemeHandler {
    private let files: [String: PandoraPreviewFile]

    init(files: [String: PandoraPreviewFile]) {
        self.files = files
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.scheme == pandoraPreviewScheme,
              url.host == pandoraPreviewHost
        else {
            urlSchemeTask.didFailWithError(NSError(
                domain: "PandoraExactPreview",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid exact preview URL"]
            ))
            return
        }

        var path = url.path
        if path.hasPrefix("/") { path.removeFirst() }
        if path.isEmpty { path = "index.html" }
        let resolved = files[path] ?? (path.split(separator: "/").last?.contains(".") == false ? files["index.html"] : nil)
        guard let file = resolved else {
            let data = Data("Not found".utf8)
            let response = URLResponse(
                url: url,
                mimeType: "text/plain",
                expectedContentLength: data.count,
                textEncodingName: "utf-8"
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
            return
        }

        let encoding = isTextMimeType(file.mimeType) ? "utf-8" : nil
        let response = URLResponse(
            url: url,
            mimeType: file.mimeType,
            expectedContentLength: file.data.count,
            textEncodingName: encoding
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(file.data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func isTextMimeType(_ mimeType: String) -> Bool {
        let value = mimeType.lowercased()
        return value.hasPrefix("text/") || value.contains("javascript") || value.contains("json") ||
            value.contains("xml") || value.contains("svg")
    }
}

final class PandoraExactPreviewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        guard let bundle = PandoraPreviewBundle.parse(args) else {
            return PandoraUnavailablePreviewView(frame: frame)
        }
        return PandoraExactPreviewView(
            frame: frame,
            viewId: viewId,
            bundle: bundle,
            messenger: messenger
        )
    }
}

private final class PandoraUnavailablePreviewView: NSObject, FlutterPlatformView {
    private let container: UIView

    init(frame: CGRect) {
        container = UIView(frame: frame)
        container.backgroundColor = .systemBackground
        super.init()
    }

    func view() -> UIView { container }
}

private final class PandoraExactPreviewView: NSObject, FlutterPlatformView, WKNavigationDelegate, WKUIDelegate, UIGestureRecognizerDelegate {
    private let webView: WKWebView
    private let selectionChannel: FlutterMethodChannel
    private let versionId: String
    private var selectionMode = false
    private var selectedSelector = ""
    private let schemeHandler: PandoraPreviewSchemeHandler
    private var selectionTap: UITapGestureRecognizer!

    init(
        frame: CGRect,
        viewId: Int64,
        bundle: PandoraPreviewBundle,
        messenger: FlutterBinaryMessenger
    ) {
        versionId = bundle.versionId
        schemeHandler = PandoraPreviewSchemeHandler(files: bundle.files)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: pandoraPreviewScheme)
        webView = WKWebView(frame: frame, configuration: configuration)
        selectionChannel = FlutterMethodChannel(
            name: "pandora/exact_preview_selection_\(viewId)",
            binaryMessenger: messenger
        )
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.allowsBackForwardNavigationGestures = false

        selectionTap = UITapGestureRecognizer(target: self, action: #selector(handleSelectionTap(_:)))
        selectionTap.delegate = self
        selectionTap.cancelsTouchesInView = false
        webView.addGestureRecognizer(selectionTap)

        selectionChannel.setMethodCallHandler { [weak self] call, result in
            self?.handleSelectionCommand(call, result: result)
        }

        let url = URL(string: "\(pandoraPreviewScheme)://\(pandoraPreviewHost)/index.html")!
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    deinit {
        selectionChannel.setMethodCallHandler(nil)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    func view() -> UIView { webView }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(url.scheme == pandoraPreviewScheme && url.host == pandoraPreviewHost ? .allow : .cancel)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }

    private func handleSelectionCommand(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setSelectionMode":
            let args = call.arguments as? [String: Any]
            selectionMode = args?["enabled"] as? Bool == true
            selectionTap.cancelsTouchesInView = selectionMode
            result(nil)
        case "setSelectedSelector":
            let args = call.arguments as? [String: Any]
            selectedSelector = (args?["selector"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            applySelectedSelector()
            result(nil)
        case "clearSelection":
            selectedSelector = ""
            applySelectedSelector()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    @objc private func handleSelectionTap(_ recognizer: UITapGestureRecognizer) {
        guard selectionMode, recognizer.state == .ended else { return }
        let point = recognizer.location(in: webView)
        probeSelection(x: point.x, y: point.y)
    }

    private func probeSelection(x: CGFloat, y: CGFloat) {
        let script = """
        (() => {
          const element = document.elementFromPoint(\(x), \(y));
          if (!element || element === document.documentElement || element === document.body) return null;
          document.querySelectorAll('[data-pandora-preview-selected="true"]').forEach(node => node.removeAttribute('data-pandora-preview-selected'));
          element.setAttribute('data-pandora-preview-selected', 'true');
          if (!document.getElementById('pandora-preview-selection-style')) {
            const style = document.createElement('style');
            style.id = 'pandora-preview-selection-style';
            style.textContent = '[data-pandora-preview-selected="true"]{outline:2px solid rgba(25,25,25,.72)!important;outline-offset:2px!important}';
            document.head.appendChild(style);
          }
          const escape = value => (window.CSS && CSS.escape) ? CSS.escape(value) : String(value).replace(/[^a-zA-Z0-9_-]/g, ch => '\\\\' + ch);
          const selectorFor = node => {
            const semanticId = node.getAttribute('data-pandora-id');
            if (semanticId) return '[data-pandora-id="' + escape(semanticId) + '"]';
            if (node.id) return '#' + escape(node.id);
            const parts = [];
            let current = node;
            while (current && current.nodeType === 1 && current !== document.documentElement) {
              let part = current.tagName.toLowerCase();
              const parent = current.parentElement;
              if (parent) {
                const peers = Array.from(parent.children).filter(child => child.tagName === current.tagName);
                if (peers.length > 1) part += ':nth-of-type(' + (peers.indexOf(current) + 1) + ')';
              }
              parts.unshift(part);
              current = parent;
              if (parts.length >= 8) break;
            }
            return parts.join(' > ');
          };
          const rect = element.getBoundingClientRect();
          const lineRaw = element.getAttribute('data-pandora-source-line');
          const sourceLine = lineRaw && /^\\d+$/.test(lineRaw) ? Number(lineRaw) : null;
          const hashRoute = location.hash && location.hash.startsWith('#/') ? location.hash.substring(1) : '';
          return JSON.stringify({
            versionId: \(jsonQuoted(versionId)),
            tag: element.tagName ? element.tagName.toLowerCase() : '',
            selector: selectorFor(element),
            text: String(element.textContent || '').trim().slice(0, 500),
            semanticId: String(element.getAttribute('data-pandora-id') || ''),
            role: String(element.getAttribute('role') || ''),
            accessibleName: String(element.getAttribute('aria-label') || element.getAttribute('title') || ''),
            route: hashRoute || '/',
            sourceFile: String(element.getAttribute('data-pandora-source-file') || 'index.html'),
            sourceLine,
            x: rect.x, y: rect.y, width: rect.width, height: rect.height
          });
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] value, _ in
            guard let self, let json = value as? String, let data = json.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  payload["versionId"] as? String == self.versionId
            else { return }
            self.selectionChannel.invokeMethod("selection", arguments: payload)
        }
    }

    private func applySelectedSelector() {
        let selector = selectedSelector
        let script: String
        if selector.isEmpty {
            script = "document.querySelectorAll('[data-pandora-preview-selected=\\\"true\\\"]').forEach(node => node.removeAttribute('data-pandora-preview-selected'));"
        } else {
            script = """
            (() => {
              document.querySelectorAll('[data-pandora-preview-selected="true"]').forEach(node => node.removeAttribute('data-pandora-preview-selected'));
              try {
                const node = document.querySelector(\(jsonQuoted(selector)));
                if (node) node.setAttribute('data-pandora-preview-selected', 'true');
              } catch (_) {}
            })()
            """
        }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

private func jsonQuoted(_ value: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: [value]),
          let encoded = String(data: data, encoding: .utf8),
          encoded.count >= 2
    else { return "\"\"" }
    return String(encoded.dropFirst().dropLast())
}
