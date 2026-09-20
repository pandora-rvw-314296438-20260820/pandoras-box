package com.banataosystems.pandora_mobile

import android.app.ActivityManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.*
import android.os.Process
import com.arm.aichat.AiChat
import com.arm.aichat.InferenceEngine
import java.io.File
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject

/**
 * Native inference lives in a separate, non-exported Android process.
 * A JNI crash or an uninterruptible decode cannot kill Flutter or its cloud request.
 */
class PandoraInferenceService : Service() {
    companion object {
        const val COMMAND = 701
        const val EVENT = 702
        private const val SYSTEM = "You are Pandora. Answer concisely using only the supplied context. " +
            "Never claim an action or provider lookup was performed. If live information, a mutation, " +
            "or a capability outside this phone is required, reply [[PANDORA_CLOUD_REQUIRED]]."
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val main = Handler(Looper.getMainLooper())
    private val nativeLock = Mutex()
    private val engine by lazy { AiChat.getInferenceEngine(applicationContext) }
    private val store by lazy { PandoraModelStore(File(noBackupFilesDir, "pandora-models")) }
    private var peer: Messenger? = null
    private var preparation: Job? = null
    private var generation: Job? = null
    private var active: PandoraModelManifest? = null
    private var loadedSha: String? = null
    private var healthTokens = 0
    private var downloadedBytes = 0L
    private var downloadedThisProcess = false
    @Volatile private var ready = false
    @Volatile private var phase = "STARTING"
    private var lastUsed = SystemClock.elapsedRealtime()
    private val messenger = Messenger(Handler(Looper.getMainLooper()) { message ->
        if (message.what != COMMAND || message.sendingUid != Process.myUid()) return@Handler true
        message.replyTo?.let { peer = it }
        try { command(JSONObject(message.data.getString("json") ?: "{}")) }
        catch (_: Exception) { publish() }
        true
    })

    override fun onBind(intent: Intent?): IBinder = messenger.binder
    override fun onDestroy() {
        ready = false
        scope.cancel()
        main.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= TRIM_MEMORY_RUNNING_LOW) {
            // Only the isolated inference process exits; active model bytes remain on disk.
            ready = false
            phase = "RECOVERING"
            publish()
            Process.killProcess(Process.myPid())
        }
    }

    private fun command(value: JSONObject) {
        when (value.optString("command")) {
            "hello" -> {
                send(JSONObject().put("type", "hello").put("pid", Process.myPid()))
                publish()
                prepareCached()
            }
            "prepare" -> prepareCached()
            "manifest" -> {
                val manifest = PandoraModelManifest.parse(value.getJSONObject("manifest"))
                acquire(manifest)
            }
            "generate" -> generate(value)
            "cancel", "unload" -> {
                ready = false
                phase = "RECOVERING"
                publish()
                // Cooperative JNI cancellation is not assumed to terminate a stuck decode.
                Process.killProcess(Process.myPid())
            }
            "resetConversation" -> Unit // Every prompt starts with a fresh KV context.
        }
    }

    private fun prepareCached() {
        if (ready || preparation?.isActive == true || generation?.isActive == true) return
        preparation = scope.launch {
            nativeLock.withLock {
                try {
                    store.recoverInterruptedTrial()
                    val candidates = listOfNotNull(store.active(), store.previous()).distinctBy { it.sha256 }
                    for (candidate in candidates) {
                        if (store.rejected(candidate) || !store.verify(candidate)) continue
                        if (activate(candidate)) break
                    }
                    if (!ready) { phase = "WAITING"; publish() }
                } catch (_: Exception) { ready = false; phase = "RECOVERING"; publish() }
            }
        }
    }

    private fun acquire(manifest: PandoraModelManifest) {
        if (preparation?.isActive == true || store.rejected(manifest)) return
        if (ready && active?.sha256 == manifest.sha256) return
        preparation = scope.launch {
            try {
                if (!admitted(manifest, cold = loadedSha == null)) return@launch
                val before = store.model(manifest).length()
                // Keep the old inference route available throughout candidate download/hash.
                if (!ready) { phase = "DOWNLOADING"; publish() }
                store.acquire(manifest) { copied -> downloadedBytes = copied; publish() }
                downloadedThisProcess = downloadedThisProcess || before != manifest.bytes
                nativeLock.withLock {
                    val previous = active ?: store.active()
                    if (!activate(manifest) && previous != null && previous.sha256 != manifest.sha256) {
                        activate(previous)
                    }
                }
            } catch (_: Exception) {
                // Partial download survives. A fresh signed grant arrives automatically.
                if (!ready) { phase = "RECOVERING"; publish() }
            }
        }
    }

    private suspend fun activate(manifest: PandoraModelManifest): Boolean {
        if (!admitted(manifest, cold = loadedSha == null)) return false
        ready = false
        phase = "INITIALIZING"
        publish()
        val deadline = Runnable { Process.killProcess(Process.myPid()) }
        main.postDelayed(deadline, 75_000)
        try {
            require(store.verify(manifest)) { "integrity_failed" }
            // Durable pending marker gives process-death rollback, not just exception rollback.
            store.beginTrial(manifest)
            withTimeout(65_000) {
                if (loadedSha != null || engine.state.value is InferenceEngine.State.Error) {
                    engine.cleanUp()
                    loadedSha = null
                }
                val state = engine.state.first {
                    it is InferenceEngine.State.Initialized ||
                        it is InferenceEngine.State.ModelReady ||
                        it is InferenceEngine.State.Error
                }
                require(state !is InferenceEngine.State.Error)
                engine.loadModel(store.model(manifest).canonicalPath)
                require(engine.state.value is InferenceEngine.State.ModelReady)
                loadedSha = manifest.sha256
                engine.setSystemPrompt(SYSTEM)
                phase = "HEALTH_TEST"
                publish()
                var tokenEvents = 0
                val output = StringBuilder()
                engine.sendUserPrompt("Reply with the word Ready.", 16).collect { token ->
                    if (token.isNotEmpty()) { tokenEvents++; output.append(token) }
                }
                require(tokenEvents > 0 && output.toString().isNotBlank())
                require(engine.state.value is InferenceEngine.State.ModelReady)
                engine.setSystemPrompt(SYSTEM)
                store.activateAfterHealthTest(manifest, tokenEvents)
                active = manifest
                healthTokens = tokenEvents
                ready = true
                phase = "LOCAL_READY"
                lastUsed = SystemClock.elapsedRealtime()
                publish()
            }
            return true
        } catch (_: Exception) {
            store.reject(manifest)
            ready = false
            phase = "RECOVERING"
            publish()
            return false
        } finally { main.removeCallbacks(deadline) }
    }

    private fun generate(value: JSONObject) {
        val requestId = value.optString("requestId")
        val prompt = value.optString("prompt")
        if (requestId.isEmpty() || prompt.isBlank() || prompt.length > 16000 ||
            !ready || generation?.isActive == true || !nativeLock.tryLock()) {
            send(JSONObject().put("type", "error").put("requestId", requestId)
                .put("message", "route_retry"))
            return
        }
        val candidate = active
        if (candidate == null || !admitted(candidate, cold = false)) {
            nativeLock.unlock()
            send(JSONObject().put("type", "error").put("requestId", requestId).put("message", "route_retry"))
            return
        }
        ready = false
        phase = "GENERATING"
        publish()
        generation = scope.launch {
            var tokens = 0
            try {
                engine.setSystemPrompt(SYSTEM)
                engine.sendUserPrompt(prompt, value.optInt("predictLength", 192).coerceIn(16, 256))
                    .collect { token ->
                        if (token.isNotEmpty()) {
                            tokens++
                            send(JSONObject().put("type", "token").put("requestId", requestId)
                                .put("text", token))
                        }
                    }
                require(tokens > 0 && engine.state.value is InferenceEngine.State.ModelReady)
                ready = true
                phase = "LOCAL_READY"
                lastUsed = SystemClock.elapsedRealtime()
                send(JSONObject().put("type", "done").put("requestId", requestId)
                    .put("tokenEvents", tokens))
            } catch (_: Exception) {
                ready = false
                phase = "RECOVERING"
                send(JSONObject().put("type", "error").put("requestId", requestId)
                    .put("message", "route_retry"))
            } finally { nativeLock.unlock(); publish() }
        }
    }

    private fun admitted(manifest: PandoraModelManifest, cold: Boolean): Boolean {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memory = ActivityManager.MemoryInfo().also(am::getMemoryInfo)
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        return Build.VERSION.SDK_INT >= manifest.minSdk &&
            Build.SUPPORTED_ABIS.contains("arm64-v8a") &&
            memory.totalMem >= manifest.minRamBytes && !memory.lowMemory &&
            memory.availMem >= (if (cold) manifest.bytes + 512L * 1024 * 1024 else 384L * 1024 * 1024) &&
            power.currentThermalStatus < PowerManager.THERMAL_STATUS_SEVERE
    }

    private fun publish() {
        val current = active
        send(JSONObject().put("type", "status").put("supported", true)
            .put("localReady", ready).put("loaded", ready).put("configured", current != null)
            .put("engineState", phase).put("healthTokenEvents", healthTokens)
            .put("modelSha256", current?.sha256).put("modelBytes", current?.bytes)
            .put("modelVersion", current?.version).put("downloadedBytes", downloadedBytes)
            .put("downloadedThisProcess", downloadedThisProcess)
            .put("modelDownloadSupported", true).put("modelDownloadResumeSupported", true)
            .put("requiresModelImport", false).put("lastUsedElapsedMs", lastUsed))
    }

    private fun send(value: JSONObject) {
        main.post {
            try {
                peer?.send(Message.obtain(null, EVENT).apply {
                    data = Bundle().apply { putString("json", value.toString()) }
                })
            } catch (_: RemoteException) { peer = null }
        }
    }
}
