package com.banataosystems.pandora_mobile

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.TimeZone
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

internal class PandoraCalendarChannel private constructor(private val context: Context) {
    private val runtime = PandoraCalendarRuntime(context)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = ThreadPoolExecutor(
        1,
        1,
        0L,
        TimeUnit.MILLISECONDS,
        ArrayBlockingQueue(8),
        { runnable -> Thread(runnable, "pandora-calendar-runtime").apply { isDaemon = true } },
        ThreadPoolExecutor.AbortPolicy()
    )

    companion object {
        private const val CHANNEL_NAME = "pandora/calendar_runtime"

        fun install(context: Context, messenger: BinaryMessenger) {
            val channel = PandoraCalendarChannel(context.applicationContext)
            MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler(channel::handleCall)
        }
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPermissionState" -> result.success(runtime.permissionState())
            "listCalendars" -> runAsync(result) { runtime.listCalendars() }
            "queryEvents" -> runAsync(result) { runtime.queryEvents(call) }
            "createEvent" -> runAsync(result) { runtime.createEvent(call) }
            "updateEvent" -> runAsync(result) { runtime.updateEvent(call) }
            "deleteEvent" -> runAsync(result) { runtime.deleteEvent(call) }
            "getOperationStatus" -> result.success(
                PandoraCalendarOperationStore.snapshot(
                    context,
                    requiredOperationId(call)
                )
            )
            "scheduleLocalReminder" -> runAsync(result) { runtime.scheduleReminder(call) }
            "cancelLocalReminder" -> runAsync(result) { runtime.cancelReminder(call) }
            "getLocalReminderStatus" -> result.success(
                PandoraReminderStateStore.snapshot(
                    context,
                    requiredOperationId(call)
                )
            )
            else -> result.notImplemented()
        }
    }

    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        try {
            executor.execute {
                val outcome = try {
                    Result.success(block())
                } catch (error: IllegalArgumentException) {
                    Result.failure<Any?>(error)
                } catch (error: SecurityException) {
                    Result.failure<Any?>(error)
                } catch (error: RuntimeException) {
                    Result.failure<Any?>(error)
                }
                mainHandler.post {
                    outcome.fold(
                        onSuccess = result::success,
                        onFailure = { error ->
                            val code = when (error) {
                                is IllegalArgumentException -> "INVALID_CALENDAR_REQUEST"
                                is SecurityException -> "CALENDAR_PERMISSION_REQUIRED"
                                else -> "CALENDAR_RUNTIME_FAILED"
                            }
                            result.error(code, error.message ?: "Calendar operation failed.", null)
                        }
                    )
                }
            }
        } catch (_: RejectedExecutionException) {
            result.error(
                "CALENDAR_RUNTIME_BUSY",
                "Pandora calendar work is busy; retry after the current bounded action completes.",
                null
            )
        }
    }

    private fun requiredOperationId(call: MethodCall): String {
        val value = call.argument<String>("operationId")?.trim().orEmpty()
        require(PandoraCalendarRuntime.OPERATION_PATTERN.matches(value)) {
            "Invalid calendar operation id."
        }
        return value
    }
}
internal class PandoraCalendarRuntime(private val context: Context) {
    companion object {
        val OPERATION_PATTERN = Regex("^[A-Za-z0-9._:-]{8,128}$")
        private val RECURRENCE_PATTERN = Regex(
            "^FREQ=(DAILY|WEEKLY|MONTHLY|YEARLY)(;[A-Z]+=[A-Z0-9,+-]+)*$"
        )
        private const val MAX_QUERY_EVENTS = 250
        private const val MAX_QUERY_WINDOW_MS = 366L * 24L * 60L * 60L * 1000L * 2L
        private const val MAX_EVENT_DURATION_MS = 366L * 24L * 60L * 60L * 1000L
    }

    fun permissionState(): Map<String, Any?> {
        val declared = requestedPermissions()
        val notificationRequired = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val exactAlarmAccess = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            alarmManager?.canScheduleExactAlarms() == true
        return mapOf(
            "schemaVersion" to "1.0.0",
            "readDeclared" to declared.contains(Manifest.permission.READ_CALENDAR),
            "readGranted" to granted(Manifest.permission.READ_CALENDAR),
            "writeDeclared" to declared.contains(Manifest.permission.WRITE_CALENDAR),
            "writeGranted" to granted(Manifest.permission.WRITE_CALENDAR),
            "notificationDeclared" to (!notificationRequired || declared.contains(Manifest.permission.POST_NOTIFICATIONS)),
            "notificationGranted" to (!notificationRequired || granted(Manifest.permission.POST_NOTIFICATIONS)),
            "exactAlarmAccess" to exactAlarmAccess
        )
    }
    fun listCalendars(): List<Map<String, Any?>> {
        requirePermission(Manifest.permission.READ_CALENDAR)
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.VISIBLE,
            CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL
        )
        val rows = mutableListOf<Map<String, Any?>>()
        context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            null,
            null,
            "${CalendarContract.Calendars.CALENDAR_DISPLAY_NAME} COLLATE NOCASE ASC"
        )?.use { cursor ->
            while (cursor.moveToNext() && rows.size < 100) {
                val access = cursor.getInt(3)
                rows += mapOf(
                    "id" to cursor.getLong(0),
                    "displayName" to cursor.getString(1).orEmpty().ifBlank { "Calendar" },
                    "visible" to (cursor.getInt(2) != 0),
                    "accessLevel" to access,
                    "writable" to (access >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR)
                )
            }
        }
        return rows
    }
    fun queryEvents(call: MethodCall): List<Map<String, Any?>> {
        requirePermission(Manifest.permission.READ_CALENDAR)
        val start = requiredLong(call, "startEpochMs")
        val end = requiredLong(call, "endEpochMs")
        requireValidRange(start, end)
        require(end - start <= MAX_QUERY_WINDOW_MS) { "Calendar query window is too large." }
        val calendarId = optionalLong(call, "calendarId")
        require(calendarId == null || calendarId > 0) { "Invalid calendar id." }
        val limit = optionalInt(call, "limit") ?: 100
        require(limit in 1..MAX_QUERY_EVENTS) { "Calendar query limit must be 1..$MAX_QUERY_EVENTS." }

        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, start)
            ContentUris.appendId(it, end)
        }.build()
        val projection = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.CALENDAR_ID,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.EVENT_TIMEZONE,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.DESCRIPTION,
            CalendarContract.Instances.RRULE,
            CalendarContract.Instances.ALL_DAY
        )
        val selection = if (calendarId == null) null else "${CalendarContract.Instances.CALENDAR_ID}=?"
        val selectionArgs = if (calendarId == null) null else arrayOf(calendarId.toString())
        val rows = mutableListOf<Map<String, Any?>>()
        context.contentResolver.query(
            uri,
            projection,
            selection,
            selectionArgs,
            "${CalendarContract.Instances.BEGIN} ASC"
        )?.use { cursor ->
            while (cursor.moveToNext() && rows.size < limit) {
                val begin = cursor.getLong(3)
                val finish = cursor.getLong(4)
                if (finish <= begin) continue
                rows += mapOf(
                    "id" to cursor.getLong(0),
                    "calendarId" to cursor.getLong(1),
                    "title" to cursor.getString(2).orEmpty().ifBlank { "Untitled event" },
                    "startEpochMs" to begin,
                    "endEpochMs" to finish,
                    "timeZoneId" to cursor.getString(5).orEmpty().ifBlank { TimeZone.getDefault().id },
                    "location" to cursor.getString(6),
                    "description" to cursor.getString(7),
                    "recurrenceRule" to cursor.getString(8),
                    "allDay" to (cursor.getInt(9) != 0)
                )
            }
        }
        return rows
    }
    fun createEvent(call: MethodCall): Map<String, Any?> {
        requireMutationPermissions()
        val operationId = requiredOperationId(call)
        val calendarId = requiredLong(call, "calendarId")
        require(calendarId > 0) { "Invalid calendar id." }
        require(calendarWritable(calendarId)) { "Target calendar is missing or not writable." }
        val input = eventInput(call)
        val fingerprint = fingerprint(
            "create|$calendarId|${input.canonical()}"
        )
        PandoraCalendarOperationStore.begin(
            context,
            operationId,
            "create",
            fingerprint
        )?.let { return it }

        val values = eventValues(calendarId, input)
        val uri = context.contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
            ?: return PandoraCalendarOperationStore.record(
                context, operationId, "create", "failed", null, "provider_insert_failed"
            )
        val eventId = ContentUris.parseId(uri)
        PandoraCalendarOperationStore.record(
            context, operationId, "create", "readback_pending", eventId, null
        )
        val readback = readEvent(eventId)
        return if (readback == null) {
            PandoraCalendarOperationStore.record(
                context, operationId, "create", "readback_failed", eventId, "event_readback_missing"
            )
        } else {
            PandoraCalendarOperationStore.record(
                context, operationId, "create", "created", eventId, null
            ) + ("event" to readback)
        }
    }

    fun updateEvent(call: MethodCall): Map<String, Any?> {
        requireMutationPermissions()
        val operationId = requiredOperationId(call)
        val eventId = requiredLong(call, "eventId")
        require(eventId > 0) { "Invalid event id." }
        val existing = readEvent(eventId)
            ?: return missingEventResult(operationId, "update", eventId)
        val calendarId = existing["calendarId"] as Long
        require(calendarWritable(calendarId)) { "Event calendar is not writable." }
        val input = eventInput(call)
        val fingerprint = fingerprint("update|$eventId|${input.canonical()}")
        PandoraCalendarOperationStore.begin(
            context, operationId, "update", fingerprint, eventId
        )?.let { return it }
        val updated = context.contentResolver.update(
            ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventId),
            eventValues(calendarId, input, includeCalendarId = false),
            null,
            null
        )
        if (updated != 1) {
            return PandoraCalendarOperationStore.record(
                context, operationId, "update", "failed", eventId, "provider_update_count_$updated"
            )
        }
        PandoraCalendarOperationStore.record(
            context, operationId, "update", "readback_pending", eventId, null
        )
        val readback = readEvent(eventId)
        return if (readback == null) {
            PandoraCalendarOperationStore.record(
                context, operationId, "update", "readback_failed", eventId, "event_readback_missing"
            )
        } else {
            PandoraCalendarOperationStore.record(
                context, operationId, "update", "updated", eventId, null
            ) + ("event" to readback)
        }
    }

    fun deleteEvent(call: MethodCall): Map<String, Any?> {
        requireMutationPermissions()
        val operationId = requiredOperationId(call)
        val eventId = requiredLong(call, "eventId")
        require(eventId > 0) { "Invalid event id." }
        val existing = readEvent(eventId)
            ?: return missingEventResult(operationId, "delete", eventId)
        val calendarId = existing["calendarId"] as Long
        require(calendarWritable(calendarId)) { "Event calendar is not writable." }
        val fingerprint = fingerprint("delete|$eventId")
        PandoraCalendarOperationStore.begin(
            context, operationId, "delete", fingerprint, eventId
        )?.let { return it }
        val deleted = context.contentResolver.delete(
            ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventId),
            null,
            null
        )
        if (deleted != 1) {
            return PandoraCalendarOperationStore.record(
                context, operationId, "delete", "failed", eventId, "provider_delete_count_$deleted"
            )
        }
        val stillPresent = readEvent(eventId) != null
        return if (stillPresent) {
            PandoraCalendarOperationStore.record(
                context, operationId, "delete", "readback_failed", eventId, "event_still_present"
            )
        } else {
            PandoraCalendarOperationStore.record(
                context, operationId, "delete", "deleted", eventId, null
            )
        }
    }
    fun scheduleReminder(call: MethodCall): Map<String, Any?> {
        val operationId = requiredOperationId(call)
        val title = requiredString(call, "title", 256)
        val body = optionalString(call, "body", 1000)
        val triggerEpochMs = requiredLong(call, "triggerEpochMs")
        val requireExact = optionalBoolean(call, "requireExact") ?: false
        val now = System.currentTimeMillis()
        require(triggerEpochMs >= now + 1000L) { "Reminder trigger must be in the future." }
        require(triggerEpochMs - now <= 5L * 366L * 24L * 60L * 60L * 1000L) {
            "Reminder trigger is outside the bounded scheduling horizon."
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requirePermission(Manifest.permission.POST_NOTIFICATIONS)
        }
        val manager = context.getSystemService(AlarmManager::class.java)
            ?: throw IllegalStateException("Android AlarmManager is unavailable.")
        val exactAllowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            manager.canScheduleExactAlarms()
        if (requireExact && !exactAllowed) {
            return mapOf(
                "operationId" to operationId,
                "state" to "special_access_required",
                "terminal" to false,
                "requiredSpecialAccess" to "exact_alarm",
                "duplicatePrevented" to false
            )
        }
        val fingerprint = fingerprint(
            "reminder|$triggerEpochMs|$requireExact|$title|${body.orEmpty()}"
        )
        PandoraReminderStateStore.begin(
            context,
            operationId,
            fingerprint,
            title,
            body,
            triggerEpochMs,
            requireExact
        )?.let { return it }
        val pendingIntent = reminderPendingIntent(operationId)
        return try {
            if (requireExact) {
                manager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerEpochMs,
                    pendingIntent
                )
            } else {
                manager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerEpochMs,
                    pendingIntent
                )
            }
            PandoraReminderStateStore.record(
                context, operationId, "scheduled", if (requireExact) true else false, null
            )
        } catch (_: SecurityException) {
            PandoraReminderStateStore.record(
                context, operationId, "failed", false, "alarm_permission_revoked_at_dispatch"
            )
        } catch (_: RuntimeException) {
            PandoraReminderStateStore.record(
                context, operationId, "failed", false, "alarm_schedule_failed"
            )
        }
    }
    fun cancelReminder(call: MethodCall): Map<String, Any?> {
        val operationId = requiredOperationId(call)
        val current = PandoraReminderStateStore.snapshot(context, operationId)
            ?: return mapOf(
                "operationId" to operationId,
                "state" to "not_found",
                "terminal" to true,
                "duplicatePrevented" to false
            )
        if (current["state"] in setOf("cancelled", "fired", "failed")) {
            return current + ("duplicatePrevented" to true)
        }
        val manager = context.getSystemService(AlarmManager::class.java)
            ?: return PandoraReminderStateStore.record(
                context, operationId, "failed", false, "alarm_manager_unavailable"
            )
        manager.cancel(reminderPendingIntent(operationId))
        return PandoraReminderStateStore.record(
            context, operationId, "cancelled", current["scheduledExact"] == true, null
        )
    }

    private fun reminderPendingIntent(operationId: String): PendingIntent {
        val intent = Intent(context, PandoraLocalReminderReceiver::class.java).apply {
            action = PandoraLocalReminderReceiver.ACTION_FIRE
            data = Uri.parse("pandora://reminder/${Uri.encode(operationId)}")
            putExtra(PandoraLocalReminderReceiver.EXTRA_OPERATION_ID, operationId)
        }
        return PendingIntent.getBroadcast(
            context,
            operationId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
    private data class EventInput(
        val title: String,
        val startEpochMs: Long,
        val endEpochMs: Long,
        val timeZoneId: String,
        val location: String?,
        val description: String?,
        val recurrenceRule: String?
    ) {
        fun canonical(): String = listOf(
            title,
            startEpochMs.toString(),
            endEpochMs.toString(),
            timeZoneId,
            location.orEmpty(),
            description.orEmpty(),
            recurrenceRule.orEmpty()
        ).joinToString("|")
    }

    private fun eventInput(call: MethodCall): EventInput {
        val title = requiredString(call, "title", 512)
        val start = requiredLong(call, "startEpochMs")
        val end = requiredLong(call, "endEpochMs")
        requireValidRange(start, end)
        require(end - start <= MAX_EVENT_DURATION_MS) { "Calendar event duration is too large." }
        val timeZoneId = requiredString(call, "timeZoneId", 128)
        require(TimeZone.getAvailableIDs().contains(timeZoneId)) { "Unknown calendar time zone." }
        val recurrence = optionalString(call, "recurrenceRule", 512)?.trim()?.takeIf { it.isNotEmpty() }
        if (recurrence != null) {
            require(!recurrence.contains('\n') && !recurrence.contains('\r')) {
                "Calendar recurrence must be a single bounded RRULE."
            }
            require(RECURRENCE_PATTERN.matches(recurrence)) {
                "Unsupported or ambiguous calendar recurrence rule."
            }
        }
        return EventInput(
            title = title,
            startEpochMs = start,
            endEpochMs = end,
            timeZoneId = timeZoneId,
            location = optionalString(call, "location", 512),
            description = optionalString(call, "description", 4000),
            recurrenceRule = recurrence
        )
    }

    private fun eventValues(
        calendarId: Long,
        input: EventInput,
        includeCalendarId: Boolean = true
    ): ContentValues = ContentValues().apply {
        if (includeCalendarId) put(CalendarContract.Events.CALENDAR_ID, calendarId)
        put(CalendarContract.Events.TITLE, input.title)
        put(CalendarContract.Events.DTSTART, input.startEpochMs)
        put(CalendarContract.Events.EVENT_TIMEZONE, input.timeZoneId)
        put(CalendarContract.Events.ALL_DAY, 0)
        put(CalendarContract.Events.EVENT_LOCATION, input.location)
        put(CalendarContract.Events.DESCRIPTION, input.description)
        if (input.recurrenceRule == null) {
            put(CalendarContract.Events.DTEND, input.endEpochMs)
            putNull(CalendarContract.Events.DURATION)
            putNull(CalendarContract.Events.RRULE)
        } else {
            putNull(CalendarContract.Events.DTEND)
            val durationSeconds = (input.endEpochMs - input.startEpochMs) / 1000L
            put(CalendarContract.Events.DURATION, "PT${durationSeconds}S")
            put(CalendarContract.Events.RRULE, input.recurrenceRule)
        }
    }

    private fun calendarWritable(calendarId: Long): Boolean {
        requirePermission(Manifest.permission.READ_CALENDAR)
        val projection = arrayOf(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL)
        context.contentResolver.query(
            ContentUris.withAppendedId(CalendarContract.Calendars.CONTENT_URI, calendarId),
            projection,
            null,
            null,
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                return cursor.getInt(0) >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR
            }
        }
        return false
    }
    private fun readEvent(eventId: Long): Map<String, Any?>? {
        requirePermission(Manifest.permission.READ_CALENDAR)
        val projection = arrayOf(
            CalendarContract.Events._ID,
            CalendarContract.Events.CALENDAR_ID,
            CalendarContract.Events.TITLE,
            CalendarContract.Events.DTSTART,
            CalendarContract.Events.DTEND,
            CalendarContract.Events.DURATION,
            CalendarContract.Events.EVENT_TIMEZONE,
            CalendarContract.Events.EVENT_LOCATION,
            CalendarContract.Events.DESCRIPTION,
            CalendarContract.Events.RRULE,
            CalendarContract.Events.ALL_DAY
        )
        context.contentResolver.query(
            ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventId),
            projection,
            null,
            null,
            null
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            val start = cursor.getLong(3)
            val rawEnd = if (cursor.isNull(4)) null else cursor.getLong(4)
            val durationSeconds = parseDurationSeconds(cursor.getString(5))
            val end = rawEnd ?: durationSeconds?.let { start + it * 1000L } ?: return null
            if (start <= 0L || end <= start) return null
            return mapOf(
                "id" to cursor.getLong(0),
                "calendarId" to cursor.getLong(1),
                "title" to cursor.getString(2).orEmpty().ifBlank { "Untitled event" },
                "startEpochMs" to start,
                "endEpochMs" to end,
                "timeZoneId" to cursor.getString(6).orEmpty().ifBlank { TimeZone.getDefault().id },
                "location" to cursor.getString(7),
                "description" to cursor.getString(8),
                "recurrenceRule" to cursor.getString(9),
                "allDay" to (cursor.getInt(10) != 0)
            )
        }
        return null
    }

    private fun parseDurationSeconds(value: String?): Long? {
        if (value.isNullOrBlank()) return null
        val seconds = Regex("^PT([0-9]{1,9})S$").matchEntire(value)?.groupValues?.get(1)
            ?.toLongOrNull()
        return seconds?.takeIf { it > 0L }
    }

    private fun missingEventResult(
        operationId: String,
        action: String,
        eventId: Long
    ): Map<String, Any?> = PandoraCalendarOperationStore.record(
        context, operationId, action, "resource_not_found", eventId, "event_not_found"
    )
    private fun requiredOperationId(call: MethodCall): String {
        val value = call.argument<String>("operationId")?.trim().orEmpty()
        require(OPERATION_PATTERN.matches(value)) { "Invalid calendar operation id." }
        return value
    }

    private fun requiredLong(call: MethodCall, key: String): Long {
        val value = call.argument<Number>(key)
            ?: throw IllegalArgumentException("$key is required.")
        return value.toLong()
    }

    private fun optionalLong(call: MethodCall, key: String): Long? =
        call.argument<Number>(key)?.toLong()

    private fun optionalInt(call: MethodCall, key: String): Int? =
        call.argument<Number>(key)?.toInt()

    private fun optionalBoolean(call: MethodCall, key: String): Boolean? =
        call.argument<Boolean>(key)

    private fun requiredString(call: MethodCall, key: String, maxLength: Int): String {
        val value = call.argument<String>(key)?.trim().orEmpty()
        require(value.isNotEmpty() && value.length <= maxLength) {
            "$key must be 1..$maxLength characters."
        }
        return value
    }
    private fun optionalString(call: MethodCall, key: String, maxLength: Int): String? {
        val value = call.argument<String>(key) ?: return null
        require(value.length <= maxLength) { "$key exceeds $maxLength characters." }
        return value
    }

    private fun requireValidRange(startEpochMs: Long, endEpochMs: Long) {
        require(startEpochMs > 0L && endEpochMs > startEpochMs) {
            "Calendar time range must be positive and ordered."
        }
    }

    private fun granted(permission: String): Boolean =
        context.packageManager.checkPermission(permission, context.packageName) ==
            PackageManager.PERMISSION_GRANTED

    private fun requirePermission(permission: String) {
        if (!granted(permission)) {
            throw SecurityException("Android permission is required: $permission")
        }
    }

    private fun requireMutationPermissions() {
        requirePermission(Manifest.permission.READ_CALENDAR)
        requirePermission(Manifest.permission.WRITE_CALENDAR)
    }

    private fun requestedPermissions(): Set<String> {
        return try {
            val info = if (Build.VERSION.SDK_INT >= 33) {
                context.packageManager.getPackageInfo(
                    context.packageName,
                    PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong())
                )
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getPackageInfo(
                    context.packageName,
                    PackageManager.GET_PERMISSIONS
                )
            }
            info.requestedPermissions?.toSet().orEmpty()
        } catch (_: PackageManager.NameNotFoundException) {
            emptySet()
        }
    }

    private fun fingerprint(value: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }
}

internal object PandoraCalendarOperationStore {
    private const val PREFS = "pandora_calendar_operation_state"
    private val lock = Any()

    fun begin(
        context: Context,
        operationId: String,
        action: String,
        fingerprint: String,
        eventId: Long? = null
    ): Map<String, Any?>? {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val existingAction = prefs.getString("$operationId.action", null)
            if (existingAction != null) {
                val existingFingerprint = prefs.getString("$operationId.fingerprint", null)
                return if (existingFingerprint == fingerprint && existingAction == action) {
                    snapshot(context, operationId)!! + ("duplicatePrevented" to true)
                } else {
                    mapOf(
                        "operationId" to operationId,
                        "action" to existingAction,
                        "state" to "operation_conflict",
                        "terminal" to true,
                        "eventId" to storedEventId(prefs, operationId),
                        "failure" to "operation_id_reused_with_different_input",
                        "duplicatePrevented" to true,
                        "updatedAtEpochMs" to System.currentTimeMillis()
                    )
                }
            }
            val editor = prefs.edit()
                .putString("$operationId.action", action)
                .putString("$operationId.fingerprint", fingerprint)
                .putString("$operationId.state", "dispatching")
                .remove("$operationId.failure")
                .putLong("$operationId.updated", System.currentTimeMillis())
            if (eventId != null) editor.putLong("$operationId.eventId", eventId)
            editor.apply()
            return null
        }
    }
    fun record(
        context: Context,
        operationId: String,
        action: String,
        state: String,
        eventId: Long?,
        failure: String?
    ): Map<String, Any?> {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val editor = prefs.edit()
                .putString("$operationId.action", action)
                .putString("$operationId.state", state)
                .putLong("$operationId.updated", System.currentTimeMillis())
            if (eventId != null) editor.putLong("$operationId.eventId", eventId)
            if (failure == null) editor.remove("$operationId.failure")
            else editor.putString("$operationId.failure", failure)
            editor.apply()
            return snapshot(context, operationId)!! + ("duplicatePrevented" to false)
        }
    }

    fun snapshot(context: Context, operationId: String): Map<String, Any?>? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val action = prefs.getString("$operationId.action", null) ?: return null
        val state = prefs.getString("$operationId.state", null) ?: return null
        val terminal = state in setOf(
            "created", "updated", "deleted", "failed", "resource_not_found", "operation_conflict"
        )
        return mapOf(
            "operationId" to operationId,
            "action" to action,
            "state" to state,
            "terminal" to terminal,
            "eventId" to storedEventId(prefs, operationId),
            "failure" to prefs.getString("$operationId.failure", null),
            "updatedAtEpochMs" to prefs.getLong("$operationId.updated", 0L)
        )
    }

    private fun storedEventId(
        prefs: android.content.SharedPreferences,
        operationId: String
    ): Long? = if (prefs.contains("$operationId.eventId")) {
        prefs.getLong("$operationId.eventId", -1L).takeIf { it > 0L }
    } else {
        null
    }
}

internal object PandoraReminderStateStore {
    private const val PREFS = "pandora_local_reminder_state"
    private val lock = Any()

    fun begin(
        context: Context,
        operationId: String,
        fingerprint: String,
        title: String,
        body: String?,
        triggerEpochMs: Long,
        requireExact: Boolean
    ): Map<String, Any?>? {        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val existingFingerprint = prefs.getString("$operationId.fingerprint", null)
            if (existingFingerprint != null) {
                return if (existingFingerprint == fingerprint) {
                    snapshot(context, operationId)!! + ("duplicatePrevented" to true)
                } else {
                    mapOf(
                        "operationId" to operationId,
                        "state" to "operation_conflict",
                        "terminal" to true,
                        "scheduledExact" to false,
                        "failure" to "operation_id_reused_with_different_input",
                        "duplicatePrevented" to true,
                        "updatedAtEpochMs" to System.currentTimeMillis()
                    )
                }
            }
            prefs.edit()
                .putString("$operationId.fingerprint", fingerprint)
                .putString("$operationId.state", "dispatching")
                .putString("$operationId.title", title)
                .putString("$operationId.body", body)
                .putLong("$operationId.trigger", triggerEpochMs)
                .putBoolean("$operationId.requireExact", requireExact)
                .putBoolean("$operationId.scheduledExact", false)
                .remove("$operationId.failure")
                .putLong("$operationId.updated", System.currentTimeMillis())
                .apply()
            return null
        }
    }
    fun record(
        context: Context,
        operationId: String,
        state: String,
        scheduledExact: Boolean,
        failure: String?
    ): Map<String, Any?> {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val editor = prefs.edit()
                .putString("$operationId.state", state)
                .putBoolean("$operationId.scheduledExact", scheduledExact)
                .putLong("$operationId.updated", System.currentTimeMillis())
            if (failure == null) editor.remove("$operationId.failure")
            else editor.putString("$operationId.failure", failure)
            editor.apply()
            return snapshot(context, operationId)!! + ("duplicatePrevented" to false)
        }
    }

    fun snapshot(context: Context, operationId: String): Map<String, Any?>? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val state = prefs.getString("$operationId.state", null) ?: return null
        val terminal = state in setOf("fired", "cancelled", "failed", "operation_conflict")
        return mapOf(
            "operationId" to operationId,
            "state" to state,
            "terminal" to terminal,
            "title" to prefs.getString("$operationId.title", null),
            "body" to prefs.getString("$operationId.body", null),
            "triggerEpochMs" to prefs.getLong("$operationId.trigger", 0L),
            "requireExact" to prefs.getBoolean("$operationId.requireExact", false),
            "scheduledExact" to prefs.getBoolean("$operationId.scheduledExact", false),
            "failure" to prefs.getString("$operationId.failure", null),
            "updatedAtEpochMs" to prefs.getLong("$operationId.updated", 0L)
        )
    }
}
class PandoraLocalReminderReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_FIRE = "com.banataosystems.pandora_mobile.LOCAL_REMINDER_FIRE"
        const val EXTRA_OPERATION_ID = "operationId"
        private const val CHANNEL_ID = "pandora_local_reminders"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_FIRE) return
        val operationId = intent.getStringExtra(EXTRA_OPERATION_ID) ?: return
        val current = PandoraReminderStateStore.snapshot(context, operationId) ?: return
        if (current["state"] != "scheduled") return
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.packageManager.checkPermission(
                Manifest.permission.POST_NOTIFICATIONS,
                context.packageName
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            PandoraReminderStateStore.record(
                context,
                operationId,
                "failed",
                current["scheduledExact"] == true,
                "notification_permission_revoked_before_fire"
            )
            return
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager == null) {
            PandoraReminderStateStore.record(
                context,
                operationId,
                "failed",
                current["scheduledExact"] == true,
                "notification_manager_unavailable"
            )
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Pandora reminders",
                    NotificationManager.IMPORTANCE_DEFAULT
                )
            )
        }
        val title = current["title"] as? String ?: "Pandora reminder"
        val body = current["body"] as? String
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val smallIcon = context.applicationInfo.icon.takeIf { it != 0 }
            ?: android.R.drawable.ic_dialog_info
        builder.setSmallIcon(smallIcon)
            .setContentTitle(title)
            .setAutoCancel(true)
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)
        if (!body.isNullOrBlank()) builder.setContentText(body)
        try {
            manager.notify(operationId.hashCode(), builder.build())
            PandoraReminderStateStore.record(
                context,
                operationId,
                "fired",
                current["scheduledExact"] == true,
                null
            )
        } catch (_: SecurityException) {
            PandoraReminderStateStore.record(
                context,
                operationId,
                "failed",
                current["scheduledExact"] == true,
                "notification_dispatch_denied"
            )
        }
    }
}
