package com.banataosystems.pandora_mobile

import android.app.Activity
import android.app.Dialog
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.speech.RecognizerIntent
import android.util.Base64
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val channelName = "pandora/native_io"
    private val speechRequest = 3101
    private val documentRequest = 3102
    private val photoRequest = 3103
    private val cameraRequest = 3104
    private val maxDocumentBytes = 32 * 1024
    private val maxImageBytes = 600 * 1024
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "pandora/exact_preview",
            PandoraExactPreviewFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler(::handleCall)
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("NATIVE_OPERATION_BUSY", "Another native input operation is already active.", null)
            return
        }
        when (call.method) {
            "speechToText" -> startSpeech(result)
            "pickTextDocument" -> startDocumentPicker(result)
            "pickPhoto" -> startPhotoPicker(result)
            "takePhoto" -> startCamera(result)
            "openExternalUrl" -> openExternalUrl(call, result)
            "openPreviewBundle" -> openPreviewBundle(call, result)
            else -> result.notImplemented()
        }
    }

    private fun openExternalUrl(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.argument<String>("url")?.trim().orEmpty()
        val uri = try { Uri.parse(raw) } catch (_: Exception) { null }
        if (uri == null || uri.scheme != "https" || uri.host.isNullOrBlank()) {
            result.error("INVALID_EXTERNAL_URL", "Only HTTPS project links can be opened.", null)
            return
        }
        val intent = Intent(Intent.ACTION_VIEW, uri)
        if (intent.resolveActivity(packageManager) == null) {
            result.error("URL_HANDLER_UNAVAILABLE", "No browser is available to open this link.", null)
            return
        }
        startActivity(intent)
        result.success(true)
    }

    private data class PreviewFile(val bytes: ByteArray, val mimeType: String)

    private fun openPreviewBundle(call: MethodCall, result: MethodChannel.Result) {
        val rawFiles = call.argument<List<Map<String, Any?>>>("files")
        if (rawFiles.isNullOrEmpty() || rawFiles.size > 1000) {
            result.error("INVALID_PREVIEW_BUNDLE", "Pandora could not open that preview safely.", null)
            return
        }
        val files = LinkedHashMap<String, PreviewFile>()
        var totalBytes = 0
        try {
            for (entry in rawFiles) {
                val path = (entry["file"] as? String)?.trim().orEmpty()
                val mimeType = (entry["mimeType"] as? String)?.trim().orEmpty()
                val dataBase64 = (entry["dataBase64"] as? String)?.trim().orEmpty()
                if (!isSafePreviewPath(path) || mimeType.isEmpty() || dataBase64.isEmpty() || files.containsKey(path)) {
                    throw IllegalArgumentException("Invalid preview file")
                }
                val bytes = Base64.decode(dataBase64, Base64.DEFAULT)
                if (bytes.size > 10 * 1024 * 1024) throw IllegalArgumentException("Preview file too large")
                totalBytes += bytes.size
                if (totalBytes > 12 * 1024 * 1024) throw IllegalArgumentException("Preview bundle too large")
                files[path] = PreviewFile(bytes, mimeType)
            }
            if (!files.containsKey("index.html")) throw IllegalArgumentException("Preview entrypoint missing")
        } catch (_: Exception) {
            result.error("INVALID_PREVIEW_BUNDLE", "Pandora could not open that preview safely.", null)
            return
        }

        val dialog = Dialog(this, android.R.style.Theme_Material_Light_NoActionBar_Fullscreen)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.WHITE)
        }
        val density = resources.displayMetrics.density
        val chrome = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = android.view.Gravity.CENTER_VERTICAL
            setPadding((8 * density).toInt(), 0, (12 * density).toInt(), 0)
            setBackgroundColor(Color.rgb(246, 245, 242))
        }
        val close = android.widget.ImageButton(this).apply {
            contentDescription = "Close preview"
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            setColorFilter(Color.rgb(23, 23, 23))
            background = null
            setOnClickListener { dialog.dismiss() }
        }
        val title = android.widget.TextView(this).apply {
            text = "Project preview"
            textSize = 15f
            setTextColor(Color.rgb(23, 23, 23))
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        }
        chrome.addView(
            close,
            LinearLayout.LayoutParams((48 * density).toInt(), (48 * density).toInt())
        )
        chrome.addView(
            title,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        )
        val webView = WebView(this)
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            mediaPlaybackRequiresUserGesture = true
            setSupportMultipleWindows(false)
        }
        webView.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
                val uri = request?.url ?: return null
                if (uri.scheme != "https" || uri.host != "pandora.local") return null
                val requested = uri.path?.removePrefix("/")?.ifBlank { "index.html" } ?: "index.html"
                val resolved = files[requested] ?: if (!requested.substringAfterLast('/').contains('.')) files["index.html"] else null
                if (resolved == null) {
                    return WebResourceResponse("text/plain", "UTF-8", ByteArrayInputStream("Not found".toByteArray()))
                }
                val encoding = if (
                    resolved.mimeType.startsWith("text/") ||
                    resolved.mimeType.contains("javascript") ||
                    resolved.mimeType.contains("json") ||
                    resolved.mimeType.contains("xml") ||
                    resolved.mimeType.contains("svg")
                ) "UTF-8" else null
                return WebResourceResponse(resolved.mimeType, encoding, ByteArrayInputStream(resolved.bytes))
            }

            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val uri = request?.url ?: return true
                return uri.scheme != "https"
            }
        }
        root.addView(
            chrome,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                (56 * density).toInt()
            )
        )
        root.addView(
            webView,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
        )
        dialog.setContentView(root)
        dialog.setOnDismissListener {
            webView.stopLoading()
            webView.destroy()
        }
        dialog.show()
        webView.loadUrl("https://pandora.local/index.html")
        result.success(true)
    }

    private fun isSafePreviewPath(path: String): Boolean {
        if (path.isBlank() || path.length > 512 || path.startsWith("/") || path.endsWith("/") || path.contains('\\') || path.contains('\u0000') || path.contains("?") || path.contains("#")) return false
        return path.split("/").none { it.isBlank() || it == "." || it == ".." || it.length > 255 }
    }

    private fun startSpeech(result: MethodChannel.Result) {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Tell Pandora what you want")
        }
        launchForResult(intent, speechRequest, result, "SPEECH_UNAVAILABLE", "No system speech recognizer is available.")
    }

    private fun startDocumentPicker(result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("text/plain", "text/markdown", "text/csv", "application/json"))
        }
        launchForResult(intent, documentRequest, result, "DOCUMENT_PICKER_UNAVAILABLE", "No system document picker is available.")
    }

    private fun startPhotoPicker(result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/jpeg", "image/png", "image/webp"))
        }
        launchForResult(intent, photoRequest, result, "PHOTO_PICKER_UNAVAILABLE", "No system photo picker is available.")
    }

    private fun startCamera(result: MethodChannel.Result) {
        val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
        launchForResult(intent, cameraRequest, result, "CAMERA_UNAVAILABLE", "No camera application is available.")
    }

    private fun launchForResult(
        intent: Intent,
        requestCode: Int,
        result: MethodChannel.Result,
        errorCode: String,
        errorMessage: String
    ) {
        if (intent.resolveActivity(packageManager) == null) {
            result.error(errorCode, errorMessage, null)
            return
        }
        pendingResult = result
        startActivityForResult(intent, requestCode)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val result = pendingResult ?: return
        if (requestCode !in setOf(speechRequest, documentRequest, photoRequest, cameraRequest)) return
        pendingResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(null)
            return
        }
        when (requestCode) {
            speechRequest -> result.success(data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull())
            documentRequest -> readDocument(data.data, result)
            photoRequest -> readPhoto(data.data, result)
            cameraRequest -> readCamera(data, result)
        }
    }

    private fun readDocument(uri: Uri?, result: MethodChannel.Result) {
        if (uri == null) { result.success(null); return }
        try {
            val name = queryDisplayName(uri) ?: "attachment.txt"
            val mimeType = contentResolver.getType(uri) ?: "text/plain"
            val text = contentResolver.openInputStream(uri).use { input ->
                if (input == null) throw IllegalStateException("The selected document cannot be opened.")
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(4096)
                var total = 0
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    total += count
                    if (total > maxDocumentBytes) throw IllegalArgumentException("The selected document is larger than 32 KB.")
                    output.write(buffer, 0, count)
                }
                output.toString(Charsets.UTF_8.name())
            }
            result.success(mapOf("name" to name, "mimeType" to mimeType, "text" to text))
        } catch (error: IllegalArgumentException) {
            result.error("DOCUMENT_TOO_LARGE", error.message, null)
        } catch (_: Exception) {
            result.error("DOCUMENT_READ_FAILED", "The selected text document could not be read.", null)
        }
    }

    private fun readPhoto(uri: Uri?, result: MethodChannel.Result) {
        if (uri == null) { result.success(null); return }
        try {
            val bitmap = contentResolver.openInputStream(uri).use { input ->
                input?.let(BitmapFactory::decodeStream)
            } ?: throw IllegalArgumentException("The selected image could not be decoded.")
            val encoded = encodeBoundedJpeg(bitmap)
            val sourceName = queryDisplayName(uri) ?: "photo"
            result.success(imagePayload(sourceName.substringBeforeLast('.') + ".jpg", encoded))
        } catch (_: Exception) {
            result.error("PHOTO_READ_FAILED", "The selected photo could not be prepared for Pandora.", null)
        }
    }

    private fun readCamera(data: Intent, result: MethodChannel.Result) {
        try {
            @Suppress("DEPRECATION")
            val bitmap = data.extras?.get("data") as? Bitmap
                ?: throw IllegalArgumentException("The camera returned no image.")
            result.success(imagePayload("camera.jpg", encodeBoundedJpeg(bitmap)))
        } catch (_: Exception) {
            result.error("CAMERA_READ_FAILED", "The camera image could not be prepared for Pandora.", null)
        }
    }

    private fun encodeBoundedJpeg(source: Bitmap): ByteArray {
        var bitmap = scaleTo(source, 1600)
        var quality = 84
        while (true) {
            val output = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, quality, output)
            val bytes = output.toByteArray()
            if (bytes.size <= maxImageBytes) return bytes
            if (quality > 55) {
                quality -= 10
                continue
            }
            val nextMax = (maxOf(bitmap.width, bitmap.height) * 0.75).toInt()
            if (nextMax < 480) throw IllegalArgumentException("Image cannot be bounded safely.")
            bitmap = scaleTo(bitmap, nextMax)
            quality = 75
        }
    }

    private fun scaleTo(source: Bitmap, maxDimension: Int): Bitmap {
        val largest = maxOf(source.width, source.height)
        if (largest <= maxDimension) return source
        val ratio = maxDimension.toDouble() / largest.toDouble()
        return Bitmap.createScaledBitmap(
            source,
            (source.width * ratio).toInt().coerceAtLeast(1),
            (source.height * ratio).toInt().coerceAtLeast(1),
            true
        )
    }

    private fun imagePayload(name: String, bytes: ByteArray) = mapOf(
        "name" to name,
        "mimeType" to "image/jpeg",
        "dataBase64" to Base64.encodeToString(bytes, Base64.NO_WRAP)
    )

    private fun queryDisplayName(uri: Uri): String? {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0) return cursor.getString(index)
        }
        return null
    }
}


private data class EmbeddedPreviewFile(val bytes: ByteArray, val mimeType: String)

private class PandoraExactPreviewFactory(
    private val messenger: io.flutter.plugin.common.BinaryMessenger
) : io.flutter.plugin.platform.PlatformViewFactory(io.flutter.plugin.common.StandardMessageCodec.INSTANCE) {
    override fun create(
        context: android.content.Context,
        viewId: Int,
        args: Any?
    ): io.flutter.plugin.platform.PlatformView {
        val params = args as? Map<*, *> ?: emptyMap<Any?, Any?>()
        return PandoraExactPreviewView(context, params, messenger, viewId)
    }
}

private class PandoraExactPreviewView(
    context: android.content.Context,
    params: Map<*, *>,
    messenger: io.flutter.plugin.common.BinaryMessenger,
    viewId: Int
) : io.flutter.plugin.platform.PlatformView {
    private val webView = WebView(context)
    private val files = LinkedHashMap<String, EmbeddedPreviewFile>()
    private val selectionChannel = MethodChannel(messenger, "pandora/exact_preview_selection_$viewId")
    private var selectionMode = false

    init {
        val rawFiles = params["files"] as? List<*>
            ?: throw IllegalArgumentException("Exact preview files are required")
        if (rawFiles.isEmpty() || rawFiles.size > 1000) {
            throw IllegalArgumentException("Invalid exact preview bundle")
        }
        var totalBytes = 0
        for (raw in rawFiles) {
            val entry = raw as? Map<*, *>
                ?: throw IllegalArgumentException("Invalid exact preview file")
            val path = (entry["file"] as? String)?.trim().orEmpty()
            val mimeType = (entry["mimeType"] as? String)?.trim().orEmpty()
            val dataBase64 = (entry["dataBase64"] as? String)?.trim().orEmpty()
            if (!isSafeEmbeddedPreviewPath(path) ||
                mimeType.isEmpty() ||
                dataBase64.isEmpty() ||
                files.containsKey(path)
            ) {
                throw IllegalArgumentException("Invalid exact preview file")
            }
            val bytes = Base64.decode(dataBase64, Base64.DEFAULT)
            if (bytes.size > 10 * 1024 * 1024) {
                throw IllegalArgumentException("Exact preview file too large")
            }
            totalBytes += bytes.size
            if (totalBytes > 12 * 1024 * 1024) {
                throw IllegalArgumentException("Exact preview bundle too large")
            }
            files[path] = EmbeddedPreviewFile(bytes, mimeType)
        }
        if (!files.containsKey("index.html")) {
            throw IllegalArgumentException("Exact preview entrypoint missing")
        }

        selectionChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setSelectionMode" -> {
                    selectionMode = call.argument<Boolean>("enabled") == true
                    if (selectionMode) clearSelectionHighlight()
                    result.success(true)
                }
                "clearSelection" -> {
                    selectionMode = false
                    clearSelectionHighlight()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        webView.setOnTouchListener { _, event ->
            if (!selectionMode) {
                false
            } else {
                if (event.actionMasked == android.view.MotionEvent.ACTION_UP) {
                    selectionMode = false
                    selectPreviewElementAt(event.x, event.y)
                }
                true
            }
        }

        webView.setBackgroundColor(Color.WHITE)
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            mediaPlaybackRequiresUserGesture = true
            setSupportMultipleWindows(false)
        }
        webView.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(
                view: WebView?,
                request: WebResourceRequest?
            ): WebResourceResponse? {
                val uri = request?.url ?: return null
                if (uri.scheme != "https" || uri.host != "pandora.local") return null
                val requested = uri.path
                    ?.removePrefix("/")
                    ?.ifBlank { "index.html" }
                    ?: "index.html"
                val resolved = files[requested]
                    ?: if (!requested.substringAfterLast('/').contains('.')) {
                        files["index.html"]
                    } else {
                        null
                    }
                if (resolved == null) {
                    return WebResourceResponse(
                        "text/plain",
                        "UTF-8",
                        ByteArrayInputStream("Not found".toByteArray())
                    )
                }
                val encoding = if (
                    resolved.mimeType.startsWith("text/") ||
                    resolved.mimeType.contains("javascript") ||
                    resolved.mimeType.contains("json") ||
                    resolved.mimeType.contains("xml") ||
                    resolved.mimeType.contains("svg")
                ) {
                    "UTF-8"
                } else {
                    null
                }
                return WebResourceResponse(
                    resolved.mimeType,
                    encoding,
                    ByteArrayInputStream(resolved.bytes)
                )
            }

            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?
            ): Boolean {
                val uri = request?.url ?: return true
                return uri.scheme != "https" || uri.host != "pandora.local"
            }
        }
        webView.loadUrl("https://pandora.local/index.html")
    }

    private fun clearSelectionHighlight() {
        webView.post {
            webView.evaluateJavascript(
                "document.querySelectorAll('.__pandora_owner_selected').forEach(function(el){el.classList.remove('__pandora_owner_selected');});",
                null
            )
        }
    }

    private fun selectPreviewElementAt(viewX: Float, viewY: Float) {
        val x = viewX.toDouble()
        val y = viewY.toDouble()
        val script = """
            (function() {
              var ratio = window.devicePixelRatio || 1;
              var el = document.elementFromPoint($x / ratio, $y / ratio);
              if (!el || el.nodeType !== 1) return null;
              function token(value) {
                return String(value || '').replace(/[^A-Za-z0-9_-]/g, '').slice(0, 60);
              }
              function selectorFor(node) {
                var parts = [];
                while (node && node.nodeType === 1 && node !== document.body && parts.length < 5) {
                  var part = String(node.tagName || 'div').toLowerCase();
                  var id = token(node.id);
                  if (id) {
                    part += '#' + id;
                    parts.unshift(part);
                    break;
                  }
                  var classes = Array.prototype.slice.call(node.classList || [])
                    .map(token)
                    .filter(Boolean)
                    .filter(function(value) { return value !== '__pandora_owner_selected'; })
                    .slice(0, 2);
                  if (classes.length) {
                    part += '.' + classes.join('.');
                  } else {
                    var index = 1;
                    var sibling = node;
                    while ((sibling = sibling.previousElementSibling) != null) {
                      if (sibling.tagName === node.tagName) index += 1;
                    }
                    if (index > 1) part += ':nth-of-type(' + index + ')';
                  }
                  parts.unshift(part);
                  node = node.parentElement;
                }
                return parts.join(' > ').slice(0, 200);
              }
              var selector = selectorFor(el);
              var text = String(el.innerText || el.getAttribute('aria-label') || el.getAttribute('title') || '')
                .replace(/\s+/g, ' ')
                .trim()
                .slice(0, 80);
              var style = document.getElementById('__pandora_owner_selection_style');
              if (!style) {
                style = document.createElement('style');
                style.id = '__pandora_owner_selection_style';
                style.textContent = '.__pandora_owner_selected{outline:2px solid #171717!important;outline-offset:2px!important;}';
                document.head.appendChild(style);
              }
              document.querySelectorAll('.__pandora_owner_selected').forEach(function(node) {
                node.classList.remove('__pandora_owner_selected');
              });
              el.classList.add('__pandora_owner_selected');
              function inheritedAttr(node, names) {
                var current = node;
                var depth = 0;
                while (current && current.nodeType === 1 && depth < 7) {
                  for (var i = 0; i < names.length; i += 1) {
                    var value = current.getAttribute(names[i]);
                    if (value) return String(value);
                  }
                  current = current.parentElement;
                  depth += 1;
                }
                return '';
              }
              var accessibleName = String(el.getAttribute('aria-label') || el.getAttribute('alt') || el.getAttribute('title') || text || '')
                .replace(/\s+/g, ' ')
                .trim()
                .slice(0, 80);
              var role = String(el.getAttribute('role') || ({BUTTON:'button',A:'link',INPUT:'textbox',TEXTAREA:'textbox',SELECT:'combobox',IMG:'img'}[String(el.tagName || '').toUpperCase()] || ''))
                .toLowerCase()
                .slice(0, 40);
              var semanticId = inheritedAttr(el, ['data-pandora-id','data-semantic-id','data-testid']) ||
                el.id || el.getAttribute('name') || accessibleName || selector;
              semanticId = String(semanticId || '').replace(/[^A-Za-z0-9_:.#\/@-]/g, '').slice(0, 160);
              var sourceFile = inheritedAttr(el, ['data-pandora-source-file','data-source-file','data-file']) || 'index.html';
              sourceFile = String(sourceFile || 'index.html').replace(/[^A-Za-z0-9_./-]/g, '').slice(0, 256) || 'index.html';
              if (sourceFile.indexOf('..') >= 0 || sourceFile.charAt(0) === '/') sourceFile = 'index.html';
              var rawSourceLine = inheritedAttr(el, ['data-pandora-source-line','data-source-line']);
              var sourceLine = parseInt(rawSourceLine || '0', 10);
              if (!Number.isFinite(sourceLine) || sourceLine < 1) sourceLine = 0;
              var rect = el.getBoundingClientRect();
              var route = String(window.location.pathname || '/').slice(0, 200);
              return JSON.stringify({
                tag:String(el.tagName || '').toLowerCase(),
                selector:selector,
                text:text,
                semanticId:semanticId,
                role:role,
                accessibleName:accessibleName,
                route:route,
                sourceFile:sourceFile,
                sourceLine:sourceLine,
                x:Number(rect.x || rect.left || 0),
                y:Number(rect.y || rect.top || 0),
                width:Number(rect.width || 0),
                height:Number(rect.height || 0)
              });
            })();
        """.trimIndent()
        webView.evaluateJavascript(script) { raw ->
            try {
                val decoded = org.json.JSONTokener(raw).nextValue()
                val json = decoded as? String ?: return@evaluateJavascript
                val payload = org.json.JSONObject(json)
                val tag = payload.optString("tag")
                    .lowercase()
                    .replace(Regex("[^a-z0-9-]"), "")
                    .take(32)
                val selector = payload.optString("selector")
                    .replace(Regex("[^A-Za-z0-9_#.:() >~\\-]"), "")
                    .trim()
                    .take(200)
                val text = payload.optString("text")
                    .replace(Regex("\\s+"), " ")
                    .trim()
                    .take(80)
                val semanticId = payload.optString("semanticId")
                    .replace(Regex("[^A-Za-z0-9_:.#/@-]"), "")
                    .take(160)
                val role = payload.optString("role")
                    .lowercase()
                    .replace(Regex("[^a-z0-9_-]"), "")
                    .take(40)
                val accessibleName = payload.optString("accessibleName")
                    .replace(Regex("\\s+"), " ")
                    .trim()
                    .take(80)
                val route = payload.optString("route")
                    .replace(Regex("[^A-Za-z0-9_./?=&%#-]"), "")
                    .take(200)
                    .ifBlank { "/" }
                var sourceFile = payload.optString("sourceFile")
                    .replace(Regex("[^A-Za-z0-9_./-]"), "")
                    .take(256)
                    .ifBlank { "index.html" }
                if (sourceFile.startsWith("/") || sourceFile.contains("..")) {
                    sourceFile = "index.html"
                }
                val sourceLine = payload.optInt("sourceLine", 0).takeIf { it > 0 }
                fun finiteNumber(key: String): Double {
                    val value = payload.optDouble(key, 0.0)
                    return if (value.isFinite()) value else 0.0
                }
                val x = finiteNumber("x")
                val y = finiteNumber("y")
                val width = finiteNumber("width").coerceAtLeast(0.0)
                val height = finiteNumber("height").coerceAtLeast(0.0)
                if (tag.isBlank() && selector.isBlank()) return@evaluateJavascript
                selectionChannel.invokeMethod(
                    "selection",
                    mapOf(
                        "tag" to tag,
                        "selector" to selector,
                        "text" to text,
                        "semanticId" to semanticId,
                        "role" to role,
                        "accessibleName" to accessibleName,
                        "route" to route,
                        "sourceFile" to sourceFile,
                        "sourceLine" to sourceLine,
                        "x" to x,
                        "y" to y,
                        "width" to width,
                        "height" to height
                    )
                )
            } catch (_: Exception) {
                clearSelectionHighlight()
            }
        }
    }

    override fun getView(): android.view.View = webView

    override fun dispose() {
        selectionChannel.setMethodCallHandler(null)
        webView.setOnTouchListener(null)
        webView.stopLoading()
        webView.destroy()
        files.clear()
    }
}

private fun isSafeEmbeddedPreviewPath(path: String): Boolean {
    if (path.isBlank() ||
        path.length > 512 ||
        path.startsWith("/") ||
        path.endsWith("/") ||
        path.contains('\\') ||
        path.contains('\u0000') ||
        path.contains("?") ||
        path.contains("#")
    ) {
        return false
    }
    return path.split("/").none {
        it.isBlank() || it == "." || it == ".." || it.length > 255
    }
}
