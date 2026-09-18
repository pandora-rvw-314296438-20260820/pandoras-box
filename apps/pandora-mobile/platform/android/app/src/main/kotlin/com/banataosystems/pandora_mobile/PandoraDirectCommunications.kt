package com.banataosystems.pandora_mobile

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.UserManager
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager

internal class PandoraDirectCommunications(private val context: Context) {
    companion object {
        private val RECIPIENT_PATTERN = Regex("^[0-9+*#(). -]{1,64}$")
        private val OPERATION_PATTERN = Regex("^[A-Za-z0-9._:-]{8,128}$")
        private val NON_DISPATCH_STATES = setOf(
            "permission_required",
            "permanently_denied",
            "restricted",
            "subscription_required"
        )
    }

    fun execute(
        operationId: String,
        kind: String,
        recipient: String,
        message: String?,
        subscriptionId: Int?,
        permissionPermanentlyDenied: Boolean
    ): Map<String, Any?> {
        require(OPERATION_PATTERN.matches(operationId)) { "Invalid operation id." }
        require(isSupportedRecipient(recipient)) { "Invalid communication recipient." }
        require(kind == "sms" || kind == "call") { "Unsupported direct communication kind." }
        require(subscriptionId == null || subscriptionId >= 0) { "Invalid subscription id." }
        if (kind == "sms") {
            require(!message.isNullOrBlank() && message.length <= 2000) { "Invalid SMS body." }
        } else {
            require(message == null) { "Direct calls cannot include an SMS body." }
        }

        val existing = PandoraCommunicationStateStore.snapshot(context, operationId)
        if (existing != null && existing["state"] !in NON_DISPATCH_STATES) {
            return existing + ("duplicatePrevented" to true)
        }

        val permission = if (kind == "sms") Manifest.permission.SEND_SMS else Manifest.permission.CALL_PHONE
        val granted = context.packageManager.checkPermission(permission, context.packageName) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) {
            val state = if (permissionPermanentlyDenied) "permanently_denied" else "permission_required"
            return PandoraCommunicationStateStore.record(context, operationId, kind, state) + mapOf(
                "requiredPermission" to permission,
                "duplicatePrevented" to false
            )
        }

        val userManager = context.getSystemService(UserManager::class.java)
        val restriction = if (kind == "sms") UserManager.DISALLOW_SMS else UserManager.DISALLOW_OUTGOING_CALLS
        if (userManager?.hasUserRestriction(restriction) == true) {
            return PandoraCommunicationStateStore.record(context, operationId, kind, "restricted") + mapOf(
                "requiredPermission" to permission,
                "duplicatePrevented" to false
            )
        }

        return if (kind == "sms") {
            executeSms(operationId, recipient, message!!, subscriptionId, permission)
        } else {
            executeCall(operationId, recipient, subscriptionId, permission)
        }
    }

    fun status(operationId: String): Map<String, Any?>? {
        require(OPERATION_PATTERN.matches(operationId)) { "Invalid operation id." }
        return PandoraCommunicationStateStore.snapshot(context, operationId)
    }

    private fun executeSms(
        operationId: String,
        recipient: String,
        message: String,
        subscriptionId: Int?,
        permission: String
    ): Map<String, Any?> {
        if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY_MESSAGING)) {
            return PandoraCommunicationStateStore.record(context, operationId, "sms", "failed", "telephony_unavailable")
        }
        if (subscriptionId == null &&
            !SubscriptionManager.isValidSubscriptionId(SmsManager.getDefaultSmsSubscriptionId())) {
            return PandoraCommunicationStateStore.record(context, operationId, "sms", "subscription_required") +
                ("requiredPermission" to permission)
        }

        val manager = smsManager(subscriptionId)
            ?: return PandoraCommunicationStateStore.record(context, operationId, "sms", "failed", "sms_manager_unavailable")
        val parts = manager.divideMessage(message)
        if (parts.isEmpty()) {
            return PandoraCommunicationStateStore.record(context, operationId, "sms", "failed", "empty_sms_parts")
        }

        synchronized(PandoraCommunicationStateStore.lock) {
            val current = PandoraCommunicationStateStore.snapshot(context, operationId)
            if (current != null && current["state"] !in NON_DISPATCH_STATES) {
                return current + ("duplicatePrevented" to true)
            }
            if (context.packageManager.checkPermission(permission, context.packageName) != PackageManager.PERMISSION_GRANTED) {
                return PandoraCommunicationStateStore.record(context, operationId, "sms", "permission_required") +
                    ("requiredPermission" to permission)
            }
            PandoraCommunicationStateStore.beginSms(context, operationId, parts.size)
        }

        val sentIntents = ArrayList<PendingIntent>(parts.size)
        val deliveryIntents = ArrayList<PendingIntent>(parts.size)
        parts.indices.forEach { index ->
            sentIntents.add(statusIntent(operationId, index, parts.size, PandoraSmsStatusReceiver.ACTION_SENT))
            deliveryIntents.add(statusIntent(operationId, index, parts.size, PandoraSmsStatusReceiver.ACTION_DELIVERED))
        }
        return try {
            if (parts.size == 1) {
                manager.sendTextMessage(recipient, null, parts[0], sentIntents[0], deliveryIntents[0])
            } else {
                manager.sendMultipartTextMessage(recipient, null, parts, sentIntents, deliveryIntents)
            }
            PandoraCommunicationStateStore.markPlatformAccepted(context, operationId)
            val afterDispatch = PandoraCommunicationStateStore.snapshot(context, operationId)!!
            val accepted = if (afterDispatch["state"] == "dispatching") {
                PandoraCommunicationStateStore.record(context, operationId, "sms", "submitted")
            } else {
                afterDispatch
            }
            accepted + mapOf(
                "requiredPermission" to permission,
                "duplicatePrevented" to false
            )
        } catch (_: SecurityException) {
            PandoraCommunicationStateStore.record(context, operationId, "sms", "failed", "permission_revoked_at_dispatch")
        } catch (_: IllegalArgumentException) {
            PandoraCommunicationStateStore.record(context, operationId, "sms", "failed", "invalid_sms_dispatch")
        } catch (_: UnsupportedOperationException) {
            PandoraCommunicationStateStore.record(context, operationId, "sms", "failed", "sms_unsupported")
        } catch (_: RuntimeException) {
            PandoraCommunicationStateStore.record(context, operationId, "sms", "failed", "sms_dispatch_failed")
        }
    }

    private fun executeCall(
        operationId: String,
        recipient: String,
        subscriptionId: Int?,
        permission: String
    ): Map<String, Any?> {
        if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY_CALLING)) {
            return PandoraCommunicationStateStore.record(context, operationId, "call", "failed", "telephony_unavailable")
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return PandoraCommunicationStateStore.record(context, operationId, "call", "fallback_required", "emergency_guard_requires_android_10")
        }
        if (subscriptionId != null) {
            val defaultVoiceSubscriptionId = try {
                SubscriptionManager.getDefaultVoiceSubscriptionId()
            } catch (_: UnsupportedOperationException) {
                SubscriptionManager.INVALID_SUBSCRIPTION_ID
            }
            if (defaultVoiceSubscriptionId != subscriptionId) {
                return PandoraCommunicationStateStore.record(
                    context,
                    operationId,
                    "call",
                    "fallback_required",
                    "explicit_call_subscription_requires_phone_ui"
                )
            }
        }
        val telephony = context.getSystemService(TelephonyManager::class.java)
            ?: return PandoraCommunicationStateStore.record(context, operationId, "call", "failed", "telephony_manager_unavailable")
        val emergency = try {
            telephony.isEmergencyNumber(recipient)
        } catch (_: RuntimeException) {
            return PandoraCommunicationStateStore.record(context, operationId, "call", "fallback_required", "emergency_check_unavailable")
        }
        if (emergency) {
            return PandoraCommunicationStateStore.record(context, operationId, "call", "fallback_required", "emergency_number")
        }

        synchronized(PandoraCommunicationStateStore.lock) {
            val current = PandoraCommunicationStateStore.snapshot(context, operationId)
            if (current != null && current["state"] !in NON_DISPATCH_STATES) {
                return current + ("duplicatePrevented" to true)
            }
            if (context.packageManager.checkPermission(permission, context.packageName) != PackageManager.PERMISSION_GRANTED) {
                return PandoraCommunicationStateStore.record(context, operationId, "call", "permission_required") +
                    ("requiredPermission" to permission)
            }
            PandoraCommunicationStateStore.record(context, operationId, "call", "dispatching")
        }

        val intent = Intent(Intent.ACTION_CALL, Uri.fromParts("tel", recipient, null))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            PandoraCommunicationStateStore.markPlatformAccepted(context, operationId)
            PandoraCommunicationStateStore.record(context, operationId, "call", "initiated") + mapOf(
                "requiredPermission" to permission,
                "duplicatePrevented" to false
            )
        } catch (_: SecurityException) {
            PandoraCommunicationStateStore.record(context, operationId, "call", "failed", "permission_revoked_at_dispatch")
        } catch (_: RuntimeException) {
            PandoraCommunicationStateStore.record(context, operationId, "call", "failed", "call_dispatch_failed")
        }
    }

    @Suppress("DEPRECATION")
    private fun smsManager(subscriptionId: Int?): SmsManager? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val base = context.getSystemService(SmsManager::class.java) ?: return null
            if (subscriptionId == null) base
            else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) base.createForSubscriptionId(subscriptionId)
            else SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
        } else {
            if (subscriptionId == null) SmsManager.getDefault()
            else SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
        }
    }

    private fun statusIntent(operationId: String, partIndex: Int, partCount: Int, action: String): PendingIntent {
        val intent = Intent(context, PandoraSmsStatusReceiver::class.java).apply {
            this.action = action
            data = Uri.parse("pandora://communication/${Uri.encode(operationId)}/$action/$partIndex")
            putExtra(PandoraSmsStatusReceiver.EXTRA_OPERATION_ID, operationId)
            putExtra(PandoraSmsStatusReceiver.EXTRA_PART_INDEX, partIndex)
            putExtra(PandoraSmsStatusReceiver.EXTRA_PART_COUNT, partCount)
        }
        val requestCode = 31 * operationId.hashCode() + partIndex + if (action == PandoraSmsStatusReceiver.ACTION_DELIVERED) 100000 else 0
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun isSupportedRecipient(recipient: String): Boolean =
        RECIPIENT_PATTERN.matches(recipient) && recipient.count(Char::isDigit) >= 3
}

internal object PandoraCommunicationStateStore {
    val lock = Any()
    private const val PREFS = "pandora_direct_communication_state"

    fun record(context: Context, operationId: String, kind: String, state: String, failure: String? = null): Map<String, Any?> {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            prefs.edit()
                .putString("$operationId.kind", kind)
                .putString("$operationId.state", state)
                .putString("$operationId.failure", failure)
                .putLong("$operationId.updated", System.currentTimeMillis())
                .apply()
            return snapshot(context, operationId)!!
        }
    }

    fun beginSms(context: Context, operationId: String, partCount: Int): Map<String, Any?> {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val editor = prefs.edit()
                .putString("$operationId.kind", "sms")
                .putString("$operationId.state", "dispatching")
                .putBoolean("$operationId.platformAccepted", false)
                .putInt("$operationId.parts", partCount)
                .putInt("$operationId.sent", 0)
                .putInt("$operationId.delivered", 0)
                .remove("$operationId.failure")
                .putLong("$operationId.updated", System.currentTimeMillis())
            for (partIndex in 0 until partCount) {
                editor.remove("$operationId.sentAck.$partIndex")
                editor.remove("$operationId.deliveredAck.$partIndex")
            }
            editor.apply()
            return snapshot(context, operationId)!!
        }
    }

    fun markPlatformAccepted(context: Context, operationId: String) {
        synchronized(lock) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean("$operationId.platformAccepted", true)
                .putLong("$operationId.platformAcceptedAt", System.currentTimeMillis())
                .apply()
        }
    }

    fun recordSmsCallback(context: Context, operationId: String, partIndex: Int, partCount: Int, delivered: Boolean, resultCode: Int) {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val currentState = prefs.getString("$operationId.state", null) ?: return
            val storedPartCount = prefs.getInt("$operationId.parts", 0)
            if (storedPartCount != partCount || partIndex !in 0 until partCount) return
            if (currentState == "failed" || currentState == "delivery_failed" || currentState == "delivered") return
            val ackKey = if (delivered) "$operationId.deliveredAck.$partIndex" else "$operationId.sentAck.$partIndex"
            if (prefs.getBoolean(ackKey, false)) return
            val editor = prefs.edit()
                .putLong("$operationId.updated", System.currentTimeMillis())
                .putBoolean(ackKey, true)
            if (resultCode != Activity.RESULT_OK) {
                editor.putString("$operationId.state", if (delivered) "delivery_failed" else "failed")
                    .putString("$operationId.failure", "android_result_$resultCode")
                    .apply()
                return
            }
            val counterKey = if (delivered) "$operationId.delivered" else "$operationId.sent"
            val count = prefs.getInt(counterKey, 0) + 1
            editor.putInt(counterKey, count)
            if (count >= partCount) editor.putString("$operationId.state", if (delivered) "delivered" else "sent")
            editor.apply()
        }
    }

    fun snapshot(context: Context, operationId: String): Map<String, Any?>? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val state = prefs.getString("$operationId.state", null) ?: return null
        val kind = prefs.getString("$operationId.kind", null) ?: return null
        val failure = prefs.getString("$operationId.failure", null)
        val terminal = state in setOf("delivered", "delivery_failed", "initiated", "failed", "fallback_required")
        return mapOf(
            "operationId" to operationId,
            "kind" to kind,
            "state" to state,
            "terminal" to terminal,
            "acceptedByPlatform" to prefs.getBoolean("$operationId.platformAccepted", false),
            "failure" to failure,
            "updatedAtEpochMs" to prefs.getLong("$operationId.updated", 0L)
        )
    }
}

class PandoraSmsStatusReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_SENT = "com.banataosystems.pandora_mobile.SMS_SENT"
        const val ACTION_DELIVERED = "com.banataosystems.pandora_mobile.SMS_DELIVERED"
        const val EXTRA_OPERATION_ID = "operationId"
        const val EXTRA_PART_INDEX = "partIndex"
        const val EXTRA_PART_COUNT = "partCount"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val operationId = intent.getStringExtra(EXTRA_OPERATION_ID) ?: return
        val partIndex = intent.getIntExtra(EXTRA_PART_INDEX, -1)
        val partCount = intent.getIntExtra(EXTRA_PART_COUNT, 0)
        if (partCount <= 0 || partIndex !in 0 until partCount) return
        when (intent.action) {
            ACTION_SENT -> PandoraCommunicationStateStore.recordSmsCallback(context, operationId, partIndex, partCount, false, resultCode)
            ACTION_DELIVERED -> PandoraCommunicationStateStore.recordSmsCallback(context, operationId, partIndex, partCount, true, resultCode)
        }
    }
}
