package com.banataosystems.pandora_mobile

import android.app.admin.DevicePolicyManager
import android.app.role.RoleManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class PandoraDeviceAgentChannel private constructor(
    private val context: Context
) {
    private val oemAdapter = PandoraAndroidOemAdapter(context)
    private val resourceRuntime = PandoraResourceRuntime(context)

    companion object {
        private const val CHANNEL_NAME = "pandora/device_agent"

        fun install(context: Context, messenger: BinaryMessenger) {
            val agent = PandoraDeviceAgentChannel(context.applicationContext)
            MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler(agent::handleCall)
        }
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCapabilityManifest" -> result.success(capabilityManifest())
            "getPermissionStates" -> result.success(permissionStates())
            "getResourceSnapshot" -> result.success(resourceRuntime.snapshot())
            "runResourceBenchmark" -> runResourceBenchmark(call, result)
            "openCommunicationComposer" -> openCommunicationComposer(call, result)
            "openSystemSurface" -> openSystemSurface(call, result)
            "runSafeDiagnostic" -> runSafeDiagnostic(call, result)
            else -> result.notImplemented()
        }
    }

    private fun runResourceBenchmark(call: MethodCall, result: MethodChannel.Result) {
        val durationMs = call.argument<Int>("durationMs")
        try {
            result.success(resourceRuntime.runBenchmark(durationMs))
        } catch (_: IllegalArgumentException) {
            result.error(
                "INVALID_RESOURCE_BENCHMARK",
                "Pandora resource benchmarks are bounded to the allowlisted local duration range.",
                null
            )
        }
    }

    private fun openSystemSurface(call: MethodCall, result: MethodChannel.Result) {
        val surface = call.argument<String>("surface")
        when (surface) {
            "app_details" -> {
                result.success(oemAdapter.openAppDetails())
                return
            }
            "battery_optimization_settings" -> {
                result.success(oemAdapter.openBatteryOptimizationSettings())
                return
            }
        }

        val intent = when (surface) {
            "android_settings" -> Intent(Settings.ACTION_SETTINGS)
            "home_app_settings" -> Intent(Settings.ACTION_HOME_SETTINGS)
            "system_dialer" -> Intent(Intent.ACTION_DIAL)
            else -> {
                result.error(
                    "UNSUPPORTED_SYSTEM_SURFACE",
                    "Pandora Device Agent only opens an allowlisted Android recovery surface.",
                    null
                )
                return
            }
        }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        if (intent.resolveActivity(context.packageManager) == null) {
            result.success(false)
            return
        }
        try {
            context.startActivity(intent)
            result.success(true)
        } catch (_: RuntimeException) {
            result.success(false)
        }
    }

    private data class RoleState(val availability: String, val reason: String)

    private fun openCommunicationComposer(call: MethodCall, result: MethodChannel.Result) {
        val kind = call.argument<String>("kind")
        val recipient = call.argument<String>("recipient")?.trim().orEmpty()
        val message = call.argument<String>("message")

        if (!Regex("^[0-9+*#(). -]{1,64}$").matches(recipient)) {
            result.error(
                "INVALID_COMMUNICATION_TARGET",
                "Pandora only accepts a bounded phone-number target for communication handoff.",
                null
            )
            return
        }
        if (kind == "call" && message != null) {
            result.error(
                "INVALID_COMMUNICATION_REQUEST",
                "Call handoffs cannot include an SMS body.",
                null
            )
            return
        }
        if (message != null && message.length > 2000) {
            result.error(
                "INVALID_COMMUNICATION_REQUEST",
                "SMS body exceeds the bounded handoff limit.",
                null
            )
            return
        }

        val handoff = when (kind) {
            "call" -> "system_dialer"
            "sms" -> "system_sms_composer"
            else -> {
                result.error(
                    "UNSUPPORTED_COMMUNICATION_KIND",
                    "Pandora only supports allowlisted call or SMS composer handoffs.",
                    null
                )
                return
            }
        }
        val intent = when (kind) {
            "call" -> Intent(Intent.ACTION_DIAL, Uri.fromParts("tel", recipient, null))
            else -> Intent(Intent.ACTION_SENDTO, Uri.fromParts("smsto", recipient, null)).apply {
                if (message != null) putExtra("sms_body", message)
            }
        }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        val status = try {
            context.startActivity(intent)
            "opened"
        } catch (_: ActivityNotFoundException) {
            "unavailable"
        } catch (_: SecurityException) {
            "unavailable"
        }
        result.success(
            mapOf(
                "kind" to kind,
                "status" to status,
                "handoff" to handoff,
                "userConfirmationRequired" to true
            )
        )
    }

    private fun androidRoleState(roleName: String, label: String): RoleState {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return RoleState(
                "unsupported",
                "Android $label role reporting requires Android 10 or newer."
            )
        }
        val manager = context.getSystemService(RoleManager::class.java)
        if (manager == null || !manager.isRoleAvailable(roleName)) {
            return RoleState(
                "unsupported",
                "Android reports that the $label role is unavailable on this device."
            )
        }
        return if (manager.isRoleHeld(roleName)) {
            RoleState(
                "available",
                "Pandora currently holds the Android $label role."
            )
        } else {
            RoleState(
                "permission_required",
                "The Android $label role is available but not held; changing it requires explicit user consent."
            )
        }
    }

    private fun isDefaultHome(): Boolean {
        val homeIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val resolved = context.packageManager.resolveActivity(
            homeIntent,
            PackageManager.MATCH_DEFAULT_ONLY
        )
        return resolved?.activityInfo?.packageName == context.packageName
    }

    private fun runSafeDiagnostic(call: MethodCall, result: MethodChannel.Result) {
        when (call.argument<String>("kind")) {
            "capability_manifest" -> result.success(
                mapOf(
                    "kind" to "capability_manifest",
                    "status" to "completed",
                    "result" to capabilityManifest()
                )
            )
            "permission_state" -> result.success(
                mapOf(
                    "kind" to "permission_state",
                    "status" to "completed",
                    "result" to permissionStates()
                )
            )
            "oem_reliability" -> result.success(
                mapOf(
                    "kind" to "oem_reliability",
                    "status" to "completed",
                    "result" to oemAdapter.reliabilityState()
                )
            )
            else -> result.error(
                "UNSUPPORTED_DEVICE_DIAGNOSTIC",
                "Pandora Device Agent only accepts an allowlisted diagnostic kind.",
                null
            )
        }
    }

    private fun capabilityManifest(): Map<String, Any?> {
        val deviceOwnerProvisioned = isDeviceOwner()
        val dialerRole = androidRoleState(RoleManager.ROLE_DIALER, "dialer")
        val smsRole = androidRoleState(RoleManager.ROLE_SMS, "SMS")
        return mapOf(
            "schemaVersion" to "1.0.0",
            "platform" to "android",
            "adapterId" to "android_public_v1",
            "sdkInt" to Build.VERSION.SDK_INT,
            "deviceOwnerProvisioned" to deviceOwnerProvisioned,
            "normalOperationRequiresDesktop" to false,
            "rootRequired" to false,
            "bootloaderUnlockRequired" to false,
            "protectedAppAccessPolicy" to "deny_private_app_data_and_credentials",
            "developmentBridgePolicy" to "optional_not_trust_dependency",
            "capabilities" to listOf(
                capability(
                    "device.identity",
                    "public_app",
                    "available",
                    "Non-sensitive Android SDK and application identity only.",
                    true
                ),
                capability(
                    "device.permission_state",
                    "public_app",
                    "available",
                    "Reads only whether selected Android permissions are declared and granted.",
                    true
                ),
                capability(
                    "device.owner_state",
                    "public_app",
                    "available",
                    "Reports actual Device Owner provisioning state without assuming authority.",
                    true
                ),
                capability(
                    "device.diagnostics.safe",
                    "public_app",
                    "available",
                    "Only allowlisted read-only Device Agent diagnostics are exposed.",
                    true
                ),
                capability(
                    "phone.home_candidate",
                    "public_app",
                    "available",
                    "Pandora declares a standard Android HOME intent and remains selectable rather than forcing itself as default.",
                    true
                ),
                capability(
                    "phone.home_role",
                    "android_role",
                    if (isDefaultHome()) "available" else "permission_required",
                    if (isDefaultHome())
                        "Android currently resolves the HOME action to Pandora."
                    else
                        "Selecting Pandora as default HOME remains a user-controlled Android boundary.",
                    true
                ),
                capability(
                    "system.settings_recovery",
                    "public_app",
                    "available",
                    "Pandora exposes a bounded route back to Android Settings.",
                    true
                ),
                capability(
                    "system.home_settings_recovery",
                    "public_app",
                    "available",
                    "Pandora exposes Android Home-app settings so the default launcher can be changed or recovered.",
                    true
                ),
                capability(
                    "system.dialer_recovery",
                    "public_app",
                    "available",
                    "Pandora can open the system dialer without CALL_PHONE permission or placing a call itself.",
                    true
                ),
                capability(
                    "phone.calls",
                    "public_app",
                    "available",
                    "Pandora hands call initiation to the system dialer with ACTION_DIAL; the user confirms the call and Pandora does not require CALL_PHONE.",
                    false
                ),
                capability(
                    "phone.sms",
                    "public_app",
                    "available",
                    "Pandora hands SMS composition to the system messaging app with ACTION_SENDTO smsto; the user confirms send and Pandora does not require SEND_SMS.",
                    false
                ),
                capability(
                    "phone.dialer_role",
                    "android_role",
                    dialerRole.availability,
                    dialerRole.reason,
                    false
                ),
                capability(
                    "phone.sms_role",
                    "android_role",
                    smsRole.availability,
                    smsRole.reason,
                    false
                ),
                capability(
                    "sensor.camera",
                    "runtime_permission",
                    "implementation_pending",
                    "Camera capability belongs to M4-005.",
                    false
                ),
                capability(
                    "sensor.microphone",
                    "runtime_permission",
                    "implementation_pending",
                    "Microphone capability belongs to M4-005.",
                    false
                ),
                capability(
                    "files.scoped_access",
                    "runtime_permission",
                    "implementation_pending",
                    "Scoped files and media capability belongs to M4-006.",
                    false
                ),
                capability(
                    "connectivity.state",
                    "public_app",
                    "implementation_pending",
                    "Connectivity capability belongs to M4-007.",
                    false
                ),
                capability(
                    "background.oem_reliability",
                    "public_app",
                    "available",
                    "Public Android/OEM reliability state and safe settings handoffs are available; Xiaomi/HyperOS autostart remains a manual OEM-controlled boundary and physical verification is required.",
                    false
                ),
                capability(
                    "resource.introspection",
                    "public_app",
                    "available",
                    "Live non-identifying CPU/GPU/RAM/storage/battery/thermal/process/network telemetry and bounded local benchmarks are available through public Android APIs; physical-device verification remains required.",
                    false
                ),
                capability(
                    "device.owner_control",
                    "device_owner",
                    if (deviceOwnerProvisioned) "implementation_pending" else "unsupported",
                    if (deviceOwnerProvisioned)
                        "Device Owner is actually provisioned; control APIs remain outside M4-001."
                    else
                        "Device Owner has not been provisioned on this installation.",
                    false
                ),
                capability(
                    "development.adb_bridge",
                    "development_only",
                    "unsupported",
                    "ADB or Wireless Debugging may assist development but is not a normal-operation dependency.",
                    false
                ),
                capability(
                    "protected_apps.private_data",
                    "policy_denied",
                    "forbidden",
                    "Pandora must not scrape credentials, OTPs, authenticator secrets, banking data, or protected app-private storage.",
                    false
                ),
                capability(
                    "shell.arbitrary",
                    "policy_denied",
                    "forbidden",
                    "The Device Agent does not expose arbitrary shell or command execution.",
                    false
                ),
                capability(
                    "root.control",
                    "policy_denied",
                    "forbidden",
                    "Root and bootloader weakening are outside the current Pandora trust model.",
                    false
                )
            )
        )
    }

    private fun capability(
        id: String,
        authority: String,
        availability: String,
        reason: String,
        normalOperationDependency: Boolean
    ): Map<String, Any?> = mapOf(
        "id" to id,
        "authority" to authority,
        "availability" to availability,
        "reason" to reason,
        "normalOperationDependency" to normalOperationDependency
    )

    private fun isDeviceOwner(): Boolean {
        val manager = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
        return manager?.isDeviceOwnerApp(context.packageName) == true
    }

    private fun permissionStates(): List<Map<String, Any?>> {
        val declared = requestedPermissions()
        return observedPermissions.map { permission ->
            mapOf(
                "permission" to permission,
                "declared" to declared.contains(permission),
                "granted" to (
                    declared.contains(permission) &&
                        context.packageManager.checkPermission(
                            permission,
                            context.packageName
                        ) == PackageManager.PERMISSION_GRANTED
                    )
            )
        }
    }

    private fun requestedPermissions(): Set<String> {
        return try {
            val info = if (Build.VERSION.SDK_INT >= 33) {
                context.packageManager.getPackageInfo(
                    context.packageName,
                    PackageManager.PackageInfoFlags.of(
                        PackageManager.GET_PERMISSIONS.toLong()
                    )
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

    private val observedPermissions = listOf(
        "android.permission.INTERNET",
        "android.permission.ACCESS_NETWORK_STATE",
        "android.permission.CAMERA",
        "android.permission.RECORD_AUDIO",
        "android.permission.READ_CONTACTS",
        "android.permission.WRITE_CONTACTS",
        "android.permission.READ_SMS",
        "android.permission.SEND_SMS",
        "android.permission.CALL_PHONE",
        "android.permission.ACCESS_FINE_LOCATION",
        "android.permission.ACCESS_COARSE_LOCATION",
        "android.permission.BLUETOOTH_SCAN",
        "android.permission.BLUETOOTH_CONNECT",
        "android.permission.READ_MEDIA_IMAGES",
        "android.permission.READ_MEDIA_VIDEO"
    )
}
