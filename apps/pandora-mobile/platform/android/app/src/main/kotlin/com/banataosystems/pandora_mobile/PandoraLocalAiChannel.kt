package com.banataosystems.pandora_mobile

import android.app.Activity
import android.app.ActivityManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Debug
import android.os.PowerManager
import android.os.SystemClock
import android.provider.OpenableColumns
import android.provider.Settings
import com.arm.aichat.AiChat
import com.arm.aichat.InferenceEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

class PandoraLocalAiChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    companion object {
        const val MODEL_PICK_REQUEST = 6107
        private const val PREFS = "pandora_local_ai"
        private const val MODEL_NAME = "model_name"
        private const val MODEL_BYTES = "model_bytes"
        private const val MODEL_SHA256 = "model_sha256"
        private const val MIN_MODEL_BYTES = 64L * 1024L * 1024L
        private const val MAX_MODEL_BYTES = 8L * 1024L * 1024L * 1024L
        private const val STORAGE_RESERVE_BYTES = 256L * 1024L * 1024L
        private const val SYSTEM_PROMPT = """
You are Pandora's fast on-device conversational layer.
Answer naturally, directly, and concisely.
Never claim you checked the internet, an account, a provider, or a device action unless verified results are included in the prompt.
If the request clearly requires live data, connected services, account data, external actions, or current web information, reply exactly [[PANDORA_CLOUD_REQUIRED]].
"""
    }

    private val methodChannel = MethodChannel(messenger, "pandora/local_ai")
    private val eventChannel = EventChannel(messenger, "pandora/local_ai_tokens")
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val preferences =
        activity.getSharedPreferences(PREFS, Activity.MODE_PRIVATE)
    private val modelDirectory = File(activity.filesDir, "pandora-local-ai")
    private val modelFile = File(modelDirectory, "model.gguf")
    private val engine by lazy {
        AiChat.getInferenceEngine(activity.applicationContext)
    }

    private var eventSink: EventChannel.EventSink? = null
    private var pendingModelResult: MethodChannel.Result? = null
    private var activeGeneration: Job? = null
    private var activeAcceptance: Job? = null
    private var loadedModelPath: String? = null
    private var lastModelLoadMs: Long? = null
    private var lastTimeToFirstTokenMs: Long? = null
    private var lastGenerationMs: Long? = null
    private var lastGeneratedTokenEvents: Int? = null
    private var lastTokenEventsPerSecond: Double? = null
    private var lastGenerationOutcome: String? = null

    init {
        eventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            },
        )
        methodChannel.setMethodCallHandler(::handleCall)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != MODEL_PICK_REQUEST) return false
        val result = pendingModelResult ?: return true
        pendingModelResult = null

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }

        scope.launch {
            try {
                unloadInternal()
                val imported = withContext(Dispatchers.IO) { importModel(uri) }
                result.success(imported)
            } catch (error: Exception) {
                result.error(
                    "LOCAL_MODEL_IMPORT_FAILED",
                    error.message ?: "Pandora could not import that GGUF model.",
                    null,
                )
            }
        }
        return true
    }

    fun close() {
        activeGeneration?.cancel()
        activeAcceptance?.cancel()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        scope.cancel()
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(statusMap())
            "pickModel" -> startModelPicker(result)
            "warm" -> warm(result)
            "generate" -> generate(call, result)
            "runAcceptance" -> runAcceptance(call, result)
            "cancel" -> {
                activeGeneration?.cancel()
                activeAcceptance?.cancel()
                activeGeneration = null
                activeAcceptance = null
                result.success(null)
            }
            "resetConversation" -> resetConversation(result)
            "unload" -> unload(result)
            else -> result.notImplemented()
        }
    }

    private fun runAcceptance(call: MethodCall, result: MethodChannel.Result) {
        if (activeGeneration?.isActive == true || activeAcceptance?.isActive == true) {
            result.error("LOCAL_AI_BUSY", "Pandora local AI is already running.", null)
            return
        }
        val sourceSha = call.argument<String>("sourceSha")?.trim()?.lowercase().orEmpty()
        val challengeNonce = call.argument<String>("challengeNonce")?.trim().orEmpty()
        val expectedApkSha256 =
            call.argument<String>("expectedApkSha256")?.trim()?.lowercase().orEmpty()
        if (!sourceSha.matches(Regex("^[0-9a-f]{40}$")) ||
            challengeNonce.isEmpty() ||
            !expectedApkSha256.matches(Regex("^[0-9a-f]{64}$"))
        ) {
            result.error(
                "LOCAL_AI_ACCEPTANCE_INVALID_CHALLENGE",
                "Pandora received an invalid physical acceptance challenge.",
                null,
            )
            return
        }

        activeAcceptance = scope.launch {
            try {
                val networkState = acceptanceNetworkState()
                if (networkState != "offline") {
                    throw IllegalStateException(
                        "Physical acceptance requires Wi-Fi and mobile data to be off.",
                    )
                }
                val emulatorDetected = isLikelyEmulator()
                if (emulatorDetected) {
                    throw IllegalStateException(
                        "Physical acceptance cannot run on an emulator.",
                    )
                }
                val modelName = preferences.getString(MODEL_NAME, null)?.trim().orEmpty()
                val modelSha256 =
                    preferences.getString(MODEL_SHA256, null)?.trim()?.lowercase().orEmpty()
                require(modelFile.isFile && modelFile.length() > 0L) {
                    "Import the local GGUF model before physical acceptance."
                }
                require(modelName.isNotEmpty()) {
                    "Pandora could not identify the imported local model."
                }
                require(modelSha256.matches(Regex("^[0-9a-f]{64}$"))) {
                    "Pandora could not verify the imported local model hash."
                }

                val apkSha256 = withContext(Dispatchers.IO) {
                    sha256File(File(activity.applicationInfo.sourceDir))
                }
                require(apkSha256 == expectedApkSha256) {
                    "Installed APK does not match the exact verified build."
                }

                unloadInternal()
                require(warmInternal()) {
                    "Pandora could not load the local model for acceptance."
                }
                val measuredLoadMs = lastModelLoadMs

                val generationStarted = SystemClock.elapsedRealtime()
                var firstTokenAt: Long? = null
                var tokenEvents = 0
                val generated = StringBuilder()
                val prompt =
                    "Offline physical acceptance challenge $challengeNonce. " +
                        "Reply with one short sentence confirming local execution."
                engine.sendUserPrompt(prompt, 96).collect { token ->
                    if (token.isNotEmpty()) {
                        val now = SystemClock.elapsedRealtime()
                        if (firstTokenAt == null) firstTokenAt = now
                        tokenEvents += 1
                        generated.append(token)
                    }
                }
                val generationMs =
                    (SystemClock.elapsedRealtime() - generationStarted).coerceAtLeast(1L)
                val ttftMs =
                    (firstTokenAt ?: throw IllegalStateException(
                        "Local acceptance generated no token.",
                    )) - generationStarted
                require(tokenEvents > 0 && generated.isNotEmpty()) {
                    "Local acceptance generated no output."
                }
                val tokenRate = tokenEvents.toDouble() * 1000.0 / generationMs.toDouble()

                var cancellationVerified = false
                val firstCancellationToken = CompletableDeferred<Unit>()
                val cancellationJob = launch {
                    try {
                        engine.sendUserPrompt(
                            "Count upward one number at a time until stopped.",
                            512,
                        ).collect { token ->
                            if (token.isNotEmpty() && !firstCancellationToken.isCompleted) {
                                firstCancellationToken.complete(Unit)
                            }
                        }
                    } catch (_: CancellationException) {
                        cancellationVerified = true
                        throw
                    }
                }
                try {
                    withTimeout(15_000L) { firstCancellationToken.await() }
                } finally {
                    cancellationJob.cancelAndJoin()
                }
                require(cancellationVerified) {
                    "Local generation cancellation did not verify."
                }

                unloadInternal()
                val unloaded = loadedModelPath == null
                val reloaded = warmInternal()
                val unloadReloadVerified = unloaded && reloaded
                require(unloadReloadVerified) {
                    "Local model unload/reload did not verify."
                }

                lastGenerationMs = generationMs
                lastTimeToFirstTokenMs = ttftMs
                lastGeneratedTokenEvents = tokenEvents
                lastTokenEventsPerSecond = tokenRate
                lastGenerationOutcome = "acceptance_completed"

                val androidId =
                    Settings.Secure.getString(
                        activity.contentResolver,
                        Settings.Secure.ANDROID_ID,
                    ).orEmpty()
                val deviceIdHash = sha256Text(
                    listOf(
                        androidId,
                        Build.FINGERPRINT,
                        Build.MANUFACTURER,
                        Build.MODEL,
                        activity.packageName,
                    ).joinToString("|"),
                )

                result.success(
                    statusMap() + mapOf(
                        "sourceSha" to sourceSha,
                        "challengeNonce" to challengeNonce,
                        "apkSha256" to apkSha256,
                        "packageName" to activity.packageName,
                        "modelName" to modelName,
                        "modelSha256" to modelSha256,
                        "deviceIdHash" to deviceIdHash,
                        "runtimeBackend" to "cpu",
                        "networkState" to networkState,
                        "localOnlyPathVerified" to true,
                        "cloudUsed" to false,
                        "physicalDevice" to true,
                        "emulatorDetected" to false,
                        "cancellationVerified" to cancellationVerified,
                        "unloadReloadVerified" to unloadReloadVerified,
                        "modelLoadMs" to measuredLoadMs,
                        "timeToFirstTokenMs" to ttftMs,
                        "generationMs" to generationMs,
                        "generatedTokenEvents" to tokenEvents,
                        "tokenEventsPerSecond" to tokenRate,
                        "generatedTextSha256" to sha256Text(generated.toString()),
                        "acceptancePromptSha256" to sha256Text(prompt),
                    ),
                )
            } catch (error: Exception) {
                result.error(
                    "LOCAL_AI_ACCEPTANCE_FAILED",
                    error.message ?: "Pandora physical acceptance failed.",
                    null,
                )
            } finally {
                activeAcceptance = null
            }
        }
    }

    private fun acceptanceNetworkState(): String {
        val manager =
            activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val active = manager.activeNetwork ?: return "offline"
        val capabilities = manager.getNetworkCapabilities(active) ?: return "offline"
        return when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile_data"
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) -> "online"
            else -> "offline"
        }
    }

    private fun isLikelyEmulator(): Boolean {
        val fingerprint = Build.FINGERPRINT.lowercase()
        val model = Build.MODEL.lowercase()
        val hardware = Build.HARDWARE.lowercase()
        val product = Build.PRODUCT.lowercase()
        return fingerprint.startsWith("generic") ||
            fingerprint.contains("emulator") ||
            model.contains("google_sdk") ||
            model.contains("emulator") ||
            model.contains("android sdk built for") ||
            hardware.contains("goldfish") ||
            hardware.contains("ranchu") ||
            product.contains("sdk_gphone") ||
            product.contains("emulator")
    }

    private fun sha256Text(value: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    private fun sha256File(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered(4 * 1024 * 1024).use { input ->
            val buffer = ByteArray(4 * 1024 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (count > 0) digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun startModelPicker(result: MethodChannel.Result) {
        if (pendingModelResult != null) {
            result.error(
                "LOCAL_MODEL_PICK_BUSY",
                "A local model picker is already open.",
                null,
            )
            return
        }
        if (activeGeneration?.isActive == true || activeAcceptance?.isActive == true) {
            result.error(
                "LOCAL_AI_BUSY",
                "Wait for the current local response to finish.",
                null,
            )
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        pendingModelResult = result
        try {
            // Do not preflight with PackageManager.resolveActivity(). On recent
            // Android builds, package visibility can return null even when the
            // system document picker is available. The benchmark app on this
            // same device already proved ACTION_OPEN_DOCUMENT works.
            activity.startActivityForResult(intent, MODEL_PICK_REQUEST)
        } catch (_: ActivityNotFoundException) {
            pendingModelResult = null
            result.error(
                "LOCAL_MODEL_PICK_UNAVAILABLE",
                "Android could not open the document picker.",
                null,
            )
        }
    }

    private fun warm(result: MethodChannel.Result) {
        scope.launch {
            try {
                result.success(warmInternal())
            } catch (error: Exception) {
                result.error(
                    "LOCAL_AI_WARM_FAILED",
                    error.message ?: "Pandora could not warm the local model.",
                    null,
                )
            }
        }
    }

    private fun generate(call: MethodCall, result: MethodChannel.Result) {
        if (activeGeneration?.isActive == true || activeAcceptance?.isActive == true) {
            result.error(
                "LOCAL_AI_BUSY",
                "Pandora local AI is already generating.",
                null,
            )
            return
        }
        val requestId = call.argument<String>("requestId")?.trim().orEmpty()
        val prompt = call.argument<String>("prompt")?.trim().orEmpty()
        val predictLength =
            (call.argument<Number>("predictLength")?.toInt() ?: 192).coerceIn(32, 512)
        if (requestId.isEmpty() || prompt.isEmpty()) {
            result.error(
                "LOCAL_AI_INVALID_PROMPT",
                "Pandora local AI received an invalid prompt.",
                null,
            )
            return
        }

        activeGeneration = scope.launch {
            val generationStarted = SystemClock.elapsedRealtime()
            var firstTokenAt: Long? = null
            var emittedTokenEvents = 0
            lastGenerationOutcome = "running"
            try {
                if (!warmInternal()) {
                    throw IllegalStateException("No local GGUF model is configured.")
                }
                engine.sendUserPrompt(prompt, predictLength).collect { token ->
                    if (token.isNotEmpty()) {
                        val now = SystemClock.elapsedRealtime()
                        if (firstTokenAt == null) {
                            firstTokenAt = now
                            lastTimeToFirstTokenMs = now - generationStarted
                        }
                        emittedTokenEvents += 1
                        eventSink?.success(
                            mapOf(
                                "requestId" to requestId,
                                "type" to "token",
                                "text" to token,
                            ),
                        )
                    }
                }
                lastGenerationOutcome = "completed"
                eventSink?.success(
                    mapOf("requestId" to requestId, "type" to "done"),
                )
            } catch (_: CancellationException) {
                lastGenerationOutcome = "cancelled"
                eventSink?.success(
                    mapOf("requestId" to requestId, "type" to "done"),
                )
            } catch (error: Exception) {
                lastGenerationOutcome = "failed"
                eventSink?.success(
                    mapOf(
                        "requestId" to requestId,
                        "type" to "error",
                        "message" to
                            (error.message ?: "Pandora local inference failed."),
                    ),
                )
            } finally {
                val elapsedMs =
                    (SystemClock.elapsedRealtime() - generationStarted).coerceAtLeast(1L)
                lastGenerationMs = elapsedMs
                lastGeneratedTokenEvents = emittedTokenEvents
                lastTokenEventsPerSecond =
                    emittedTokenEvents.toDouble() * 1000.0 / elapsedMs.toDouble()
                activeGeneration = null
            }
        }
        result.success(true)
    }

    private fun resetConversation(result: MethodChannel.Result) {
        scope.launch {
            try {
                activeGeneration?.cancel()
                activeGeneration = null
                unloadInternal()
                result.success(warmInternal())
            } catch (error: Exception) {
                result.error(
                    "LOCAL_AI_RESET_FAILED",
                    error.message ?: "Pandora could not reset local context.",
                    null,
                )
            }
        }
    }

    private fun unload(result: MethodChannel.Result) {
        scope.launch {
            try {
                activeGeneration?.cancel()
                activeGeneration = null
                unloadInternal()
                result.success(null)
            } catch (error: Exception) {
                result.error(
                    "LOCAL_AI_UNLOAD_FAILED",
                    error.message ?: "Pandora could not unload the local model.",
                    null,
                )
            }
        }
    }

    private suspend fun warmInternal(): Boolean {
        if (!modelFile.isFile || modelFile.length() <= 0L) return false
        val canonicalPath = modelFile.canonicalPath
        if (loadedModelPath == canonicalPath &&
            engine.state.value is InferenceEngine.State.ModelReady
        ) {
            return true
        }

        awaitEngineInitialized()
        if (loadedModelPath != null) unloadInternal()
        val loadStarted = SystemClock.elapsedRealtime()
        engine.loadModel(canonicalPath)
        engine.setSystemPrompt(SYSTEM_PROMPT.trim())
        lastModelLoadMs = SystemClock.elapsedRealtime() - loadStarted
        loadedModelPath = canonicalPath
        return true
    }

    private suspend fun awaitEngineInitialized() {
        withTimeout(15_000L) {
            when (val current = engine.state.value) {
                is InferenceEngine.State.Initialized -> return@withTimeout
                is InferenceEngine.State.ModelReady -> return@withTimeout
                is InferenceEngine.State.Error -> {
                    engine.cleanUp()
                    return@withTimeout
                }
                else -> {
                    val ready = engine.state.first {
                        it is InferenceEngine.State.Initialized ||
                            it is InferenceEngine.State.ModelReady ||
                            it is InferenceEngine.State.Error
                    }
                    if (ready is InferenceEngine.State.Error) {
                        engine.cleanUp()
                    }
                }
            }
        }
    }

    private suspend fun unloadInternal() {
        val state = engine.state.value
        if (loadedModelPath != null &&
            (state is InferenceEngine.State.ModelReady ||
                state is InferenceEngine.State.Error)
        ) {
            engine.cleanUp()
        }
        loadedModelPath = null
    }

    private fun importModel(uri: Uri): Map<String, Any?> {
        val metadata = queryModelMetadata(uri)
        val displayName = metadata.first
        val declaredBytes = metadata.second
        require(displayName.lowercase().endsWith(".gguf")) {
            "Choose a .gguf model file."
        }
        if (declaredBytes != null) {
            require(declaredBytes in MIN_MODEL_BYTES..MAX_MODEL_BYTES) {
                "The selected GGUF size is outside Pandora's supported range."
            }
        }

        modelDirectory.mkdirs()
        val initialUsableBytes = modelDirectory.usableSpace
        require(initialUsableBytes > STORAGE_RESERVE_BYTES + MIN_MODEL_BYTES) {
            "Pandora does not have enough free storage for a local GGUF model."
        }
        if (declaredBytes != null) {
            require(declaredBytes + STORAGE_RESERVE_BYTES <= initialUsableBytes) {
                "Pandora does not have enough free storage for this GGUF model."
            }
        }
        val temporary = File(modelDirectory, "model.gguf.importing")
        if (temporary.exists()) temporary.delete()

        val digest = MessageDigest.getInstance("SHA-256")
        var copied = 0L
        activity.contentResolver.openInputStream(uri).use { input ->
            require(input != null) { "Android could not read the selected GGUF." }
            temporary.outputStream().buffered(4 * 1024 * 1024).use { output ->
                val buffer = ByteArray(4 * 1024 * 1024)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (count == 0) continue
                    copied += count
                    require(copied <= MAX_MODEL_BYTES) {
                        "The selected GGUF is too large."
                    }
                    require(modelDirectory.usableSpace > STORAGE_RESERVE_BYTES) {
                        "Pandora ran out of safe free storage while importing the GGUF."
                    }
                    digest.update(buffer, 0, count)
                    output.write(buffer, 0, count)
                }
                output.flush()
            }
        }

        require(copied >= MIN_MODEL_BYTES) {
            "The selected file is too small to be a supported GGUF model."
        }
        if (modelFile.exists() && !modelFile.delete()) {
            temporary.delete()
            error("Pandora could not replace the previous local model.")
        }
        if (!temporary.renameTo(modelFile)) {
            temporary.copyTo(modelFile, overwrite = true)
            temporary.delete()
        }

        val sha256 = digest.digest().joinToString("") { "%02x".format(it) }
        preferences.edit()
            .putString(MODEL_NAME, displayName)
            .putLong(MODEL_BYTES, copied)
            .putString(MODEL_SHA256, sha256)
            .apply()
        return statusMap()
    }

    private fun queryModelMetadata(uri: Uri): Pair<String, Long?> {
        var name = "model.gguf"
        var size: Long? = null
        activity.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (nameIndex >= 0) {
                    name = cursor.getString(nameIndex)?.trim().orEmpty().ifEmpty {
                        name
                    }
                }
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                    size = cursor.getLong(sizeIndex)
                }
            }
        }
        return name to size
    }

    private fun statusMap(): Map<String, Any?> {
        val configured = modelFile.isFile && modelFile.length() > 0L
        val activityManager =
            activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memory = ActivityManager.MemoryInfo().also(activityManager::getMemoryInfo)
        val processMemory = Debug.MemoryInfo().also(Debug::getMemoryInfo)
        val batteryManager =
            activity.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val powerManager =
            activity.getSystemService(Context.POWER_SERVICE) as PowerManager
        val featureNames =
            activity.packageManager.systemAvailableFeatures
                .mapNotNull { it.name }
                .toSet()
        val vulkanFeatureExposed =
            featureNames.any {
                it == "android.hardware.vulkan.level" ||
                    it == "android.hardware.vulkan.version"
            }
        val thermalStatus =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                thermalStatusName(powerManager.currentThermalStatus)
            } else {
                null
            }
        val batteryPercent =
            batteryManager
                .getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                .takeIf { it in 0..100 }

        return mapOf(
            "supported" to true,
            "configured" to configured,
            "loaded" to
                (loadedModelPath != null &&
                    engine.state.value is InferenceEngine.State.ModelReady),
            "modelName" to preferences.getString(MODEL_NAME, null),
            "modelPath" to if (configured) modelFile.absolutePath else null,
            "modelBytes" to
                if (configured) {
                    preferences.getLong(MODEL_BYTES, modelFile.length())
                } else {
                    null
                },
            "modelSha256" to preferences.getString(MODEL_SHA256, null),
            "requiresModelImport" to !configured,
            "modelImportMethod" to "android_document_picker",
            "modelDownloadSupported" to false,
            "modelDownloadResumeSupported" to false,
            "engineState" to engine.state.value.javaClass.simpleName,
            "nativeRuntime" to "llama.cpp",
            "runtimeBackendConfigured" to "cpu",
            "cpuOptimizationConfigured" to "KleidiAI+OpenMP",
            "runtimeNativeAbi" to "arm64-v8a",
            "gpuAccelerationUsed" to false,
            "npuAccelerationUsed" to false,
            "nnapiAccelerationUsed" to false,
            "acceleratorVerified" to false,
            "lastModelLoadMs" to lastModelLoadMs,
            "lastTimeToFirstTokenMs" to lastTimeToFirstTokenMs,
            "lastGenerationMs" to lastGenerationMs,
            "lastGeneratedTokenEvents" to lastGeneratedTokenEvents,
            "tokensPerSecond" to lastTokenEventsPerSecond,
            "tokensPerSecondBasis" to "non_empty_inference_flow_emissions",
            "lastGenerationOutcome" to lastGenerationOutcome,
            "androidVersion" to Build.VERSION.RELEASE,
            "androidSdk" to Build.VERSION.SDK_INT,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "device" to Build.DEVICE,
            "product" to Build.PRODUCT,
            "hardware" to Build.HARDWARE,
            "board" to Build.BOARD,
            "socManufacturer" to
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    Build.SOC_MANUFACTURER
                } else {
                    null
                },
            "socModel" to
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    Build.SOC_MODEL
                } else {
                    null
                },
            "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
            "cpuArchitecture" to Build.SUPPORTED_ABIS.firstOrNull(),
            "cpuCores" to Runtime.getRuntime().availableProcessors(),
            "totalRamBytes" to memory.totalMem,
            "availableRamBytes" to memory.availMem,
            "memoryLow" to memory.lowMemory,
            "memoryPressureThresholdBytes" to memory.threshold,
            "processPssBytes" to processMemory.totalPss.toLong() * 1024L,
            "totalStorageBytes" to modelDirectory.totalSpace,
            "availableStorageBytes" to modelDirectory.usableSpace,
            "batteryPercent" to batteryPercent,
            "charging" to
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    batteryManager.isCharging
                } else {
                    null
                },
            "thermalStatus" to thermalStatus,
            "nnapiApiAvailable" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1),
            "vulkanFeatureExposed" to vulkanFeatureExposed,
            "openClSupport" to null,
            "openClProbe" to "not_exposed_by_public_android_api",
            "gpu" to null,
            "gpuProbe" to "not_exposed_without_runtime_graphics_probe",
            "npu" to null,
            "npuProbe" to "not_exposed_by_standard_android_api",
        )
    }

    private fun thermalStatusName(status: Int): String =
        when (status) {
            PowerManager.THERMAL_STATUS_NONE -> "none"
            PowerManager.THERMAL_STATUS_LIGHT -> "light"
            PowerManager.THERMAL_STATUS_MODERATE -> "moderate"
            PowerManager.THERMAL_STATUS_SEVERE -> "severe"
            PowerManager.THERMAL_STATUS_CRITICAL -> "critical"
            PowerManager.THERMAL_STATUS_EMERGENCY -> "emergency"
            PowerManager.THERMAL_STATUS_SHUTDOWN -> "shutdown"
            else -> "unknown"
        }
}
