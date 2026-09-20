package com.banataosystems.pandora_mobile

import android.app.Activity
import android.content.*
import android.os.*
import android.os.Process
import io.flutter.plugin.common.*
import org.json.JSONArray
import org.json.JSONObject

/** Flutter only owns IPC and deadlines; it never loads a native inference library. */
class PandoraLocalAiChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    companion object { const val MODEL_PICK_REQUEST = 6107 }
    private val methods = MethodChannel(messenger, "pandora/local_ai")
    private val events = EventChannel(messenger, "pandora/local_ai_tokens")
    private val handler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var remote: Messenger? = null
    private var bound = false
    private var closed = false
    private var suspended = false
    private var workerPid: Int? = null
    private var requestId: String? = null
    private var requestStarted = 0L
    private var lastTokenAt = 0L
    private var firstToken = false
    private var retries = 0
    private var status = unavailable()
    private var manifest: JSONObject? = null

    private val inbox = Messenger(Handler(Looper.getMainLooper()) { message ->
        if (message.what != PandoraInferenceService.EVENT ||
            message.sendingUid != Process.myUid()) return@Handler true
        try { receive(JSONObject(message.data.getString("json") ?: "{}")) }
        catch (_: Exception) { failRequest() }
        true
    })
    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            remote = Messenger(binder)
            send(JSONObject().put("command", "hello"))
            manifest?.let { send(JSONObject().put("command", "manifest").put("manifest", it)) }
        }
        override fun onServiceDisconnected(name: ComponentName) { lost() }
        override fun onBindingDied(name: ComponentName) { lost() }
        override fun onNullBinding(name: ComponentName) { lost() }
    }
    private val watchdog = object : Runnable {
        override fun run() {
            if (closed) return
            val now = SystemClock.elapsedRealtime()
            if (requestId != null && (
                    (!firstToken && now - requestStarted > 2500) ||
                    (firstToken && now - lastTokenAt > 5000) ||
                    now - requestStarted > 25_000)) {
                failRequest()
                retire(recover = true)
            }
            handler.postDelayed(this, 200)
        }
    }

    init {
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink?) { sink = eventSink }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(status)
                "prepare", "warm" -> {
                    suspended = false
                    bind()
                    send(JSONObject().put("command", "prepare"))
                    result.success(status["localReady"] == true)
                }
                "configure" -> {
                    try {
                        val value = JSONObject(call.arguments as Map<*, *>)
                        PandoraModelManifest.parse(value) // Reject malformed metadata before IPC.
                        manifest = value
                        if (!suspended) bind()
                        send(JSONObject().put("command", "manifest").put("manifest", value))
                        result.success(null)
                    } catch (_: Exception) { result.error("CONFIG_INVALID", "route_retry", null) }
                }
                "generate" -> {
                    val id = call.argument<String>("requestId").orEmpty()
                    if (status["localReady"] != true || requestId != null || remote == null) {
                        result.success(false)
                    } else {
                        requestId = id
                        firstToken = false
                        requestStarted = SystemClock.elapsedRealtime()
                        lastTokenAt = requestStarted
                        status = status + mapOf("localReady" to false, "loaded" to false)
                        val sent = send(JSONObject().put("command", "generate").put("requestId", id)
                            .put("prompt", call.argument<String>("prompt"))
                            .put("predictLength", call.argument<Number>("predictLength")?.toInt() ?: 192))
                        result.success(sent)
                        if (!sent) failRequest()
                    }
                }
                "resetConversation" -> result.success(null)
                "cancel" -> {
                    if (requestId != null) { failRequest(); retire(recover = true) }
                    result.success(null)
                }
                "unload" -> {
                    suspended = true
                    failRequest()
                    retire(recover = false)
                    result.success(null)
                }
                // Kept as a compatibility denial; customer navigation has no model controls.
                "pickModel", "runAcceptance" -> result.error("INTERNAL_ONLY", "Unavailable", null)
                else -> result.notImplemented()
            }
        }
        bind()
        handler.post(watchdog)
    }

    private fun bind() {
        if (bound || closed || suspended) return
        status = unavailable()
        try {
            bound = activity.bindService(
                Intent(activity, PandoraInferenceService::class.java),
                connection, Context.BIND_AUTO_CREATE,
            )
        } catch (_: Exception) { bound = false }
    }

    private fun send(value: JSONObject): Boolean = try {
        val target = remote
        if (target == null) false else {
            target.send(Message.obtain(null, PandoraInferenceService.COMMAND).apply {
                replyTo = inbox
                data = Bundle().apply { putString("json", value.toString()) }
            })
            true
        }
    } catch (_: RemoteException) { false }

    private fun receive(value: JSONObject) {
        when (value.optString("type")) {
            "hello" -> workerPid = value.optInt("pid").takeIf { it > 0 && it != Process.myPid() }
            "status" -> {
                status = jsonMap(value)
                if (status["localReady"] == true) retries = 0
                // After cold-cache preparation finishes, retry any grant received while it was busy.
                if (requestId == null && status["engineState"] == "WAITING") {
                    manifest?.let { send(JSONObject().put("command", "manifest").put("manifest", it)) }
                }
            }
            "token", "done", "error" -> {
                if (value.optString("requestId") != requestId) return
                val kind = value.optString("type")
                if (kind == "token") { firstToken = true; lastTokenAt = SystemClock.elapsedRealtime() }
                sink?.success(jsonMap(value))
                if (kind != "token") {
                    requestId = null
                    if (kind == "error") retire(recover = true)
                }
            }
        }
    }

    private fun failRequest() {
        val id = requestId ?: return
        requestId = null
        sink?.success(mapOf("type" to "error", "requestId" to id, "message" to "route_retry"))
    }

    private fun lost() {
        if (closed) return
        failRequest()
        retire(recover = true)
    }

    private fun retire(recover: Boolean) {
        status = unavailable()
        remote = null
        val pid = workerPid
        workerPid = null
        if (bound) {
            bound = false
            try { activity.unbindService(connection) } catch (_: Exception) { }
        }
        if (pid != null && pid != Process.myPid()) {
            try { Process.killProcess(pid) } catch (_: Exception) { }
        }
        if (recover && !closed && !suspended) {
            retries++
            val delay = (5000L * (1L shl retries.coerceAtMost(4))).coerceAtMost(60_000)
            handler.postDelayed({ bind() }, delay)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean = false
    fun close() {
        closed = true
        failRequest()
        retire(recover = false)
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        handler.removeCallbacksAndMessages(null)
    }

    private fun unavailable(): Map<String, Any?> = mapOf(
        "supported" to true, "configured" to false, "loaded" to false,
        "localReady" to false, "engineState" to "RECOVERING",
        "modelDownloadSupported" to true, "modelDownloadResumeSupported" to true,
        "requiresModelImport" to false,
    )

    private fun jsonMap(value: JSONObject): Map<String, Any?> =
        value.keys().asSequence().associateWith { key ->
            when (val item = value.get(key)) {
                JSONObject.NULL -> null
                is JSONObject -> jsonMap(item)
                is JSONArray -> (0 until item.length()).map { item.opt(it) }
                else -> item
            }
        }
}
