package com.banataosystems.pandora_mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.speech.RecognizerIntent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val channelName = "pandora/native_io"
    private val speechRequest = 3101
    private val documentRequest = 3102
    private val maxDocumentBytes = 32 * 1024
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler(::handleCall)
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error(
                "NATIVE_OPERATION_BUSY",
                "Another native input operation is already active.",
                null
            )
            return
        }
        when (call.method) {
            "speechToText" -> startSpeech(result)
            "pickTextDocument" -> startDocumentPicker(result)
            "openExternalUrl" -> openExternalUrl(call, result)
            else -> result.notImplemented()
        }
    }

    private fun openExternalUrl(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.argument<String>("url")?.trim().orEmpty()
        val uri = try {
            Uri.parse(raw)
        } catch (_: Exception) {
            null
        }
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

    private fun startSpeech(result: MethodChannel.Result) {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Tell Pandora what you want")
        }
        if (intent.resolveActivity(packageManager) == null) {
            result.error(
                "SPEECH_UNAVAILABLE",
                "No system speech recognizer is available.",
                null
            )
            return
        }
        pendingResult = result
        startActivityForResult(intent, speechRequest)
    }

    private fun startDocumentPicker(result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "text/plain",
                    "text/markdown",
                    "text/csv",
                    "application/json"
                )
            )
        }
        if (intent.resolveActivity(packageManager) == null) {
            result.error(
                "DOCUMENT_PICKER_UNAVAILABLE",
                "No system document picker is available.",
                null
            )
            return
        }
        pendingResult = result
        startActivityForResult(intent, documentRequest)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val result = pendingResult ?: return
        if (requestCode != speechRequest && requestCode != documentRequest) {
            return
        }
        pendingResult = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(null)
            return
        }

        if (requestCode == speechRequest) {
            val matches =
                data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
            result.success(matches?.firstOrNull())
            return
        }

        val uri = data.data
        if (uri == null) {
            result.success(null)
            return
        }
        try {
            val name = queryDisplayName(uri) ?: "attachment.txt"
            val mimeType = contentResolver.getType(uri) ?: "text/plain"
            val text = contentResolver.openInputStream(uri).use { input ->
                if (input == null) {
                    throw IllegalStateException("The selected document cannot be opened.")
                }
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(4096)
                var total = 0
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    total += count
                    if (total > maxDocumentBytes) {
                        throw IllegalArgumentException(
                            "The selected document is larger than 32 KB."
                        )
                    }
                    output.write(buffer, 0, count)
                }
                output.toString(Charsets.UTF_8.name())
            }
            result.success(
                mapOf(
                    "name" to name,
                    "mimeType" to mimeType,
                    "text" to text
                )
            )
        } catch (error: IllegalArgumentException) {
            result.error("DOCUMENT_TOO_LARGE", error.message, null)
        } catch (error: Exception) {
            result.error(
                "DOCUMENT_READ_FAILED",
                "The selected text document could not be read.",
                null
            )
        }
    }

    private fun queryDisplayName(uri: android.net.Uri): String? {
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0) return cursor.getString(index)
        }
        return null
    }
}
