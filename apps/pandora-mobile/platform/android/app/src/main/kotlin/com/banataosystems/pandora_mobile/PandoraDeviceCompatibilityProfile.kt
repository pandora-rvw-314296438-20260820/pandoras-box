package com.banataosystems.pandora_mobile

import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.StatFs

internal class PandoraDeviceCompatibilityProfile(
    private val context: Context,
    private val oemAdapter: PandoraAndroidOemAdapter
) {
    fun snapshot(
        deviceOwnerProvisioned: Boolean,
        homeRoleHeld: Boolean,
        dialerRoleAvailability: String,
        smsRoleAvailability: String
    ): Map<String, Any?> {
        val activityManager = context.getSystemService(ActivityManager::class.java)
        val memory = ActivityManager.MemoryInfo()
        if (activityManager != null) activityManager.getMemoryInfo(memory)
        val storage = StatFs(context.filesDir.absolutePath)
        val oem = oemAdapter.reliabilityState()
        val packageManager = context.packageManager
        return mapOf(
            "schemaVersion" to "1.0.0",
            "platform" to "android",
            "sdkInt" to Build.VERSION.SDK_INT,
            "cpu" to mapOf(
                "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
                "logicalProcessors" to Runtime.getRuntime().availableProcessors().coerceAtLeast(1),
                "source" to "android_public_runtime"
            ),
            "memory" to mapOf(
                "totalBytes" to if (activityManager != null) memory.totalMem else null,
                "source" to "activity_manager_public"
            ),
            "storage" to mapOf(
                "scope" to "app_data_filesystem",
                "totalBytes" to storage.totalBytes,
                "availableBytes" to storage.availableBytes,
                "source" to "statfs_public"
            ),
            "accelerators" to mapOf(
                "npu" to mapOf(
                    "availability" to "unknown",
                    "evidence" to "not_probed_by_stable_public_api"
                )
            ),
            "roles" to mapOf(
                "deviceOwnerProvisioned" to deviceOwnerProvisioned,
                "homeRoleHeld" to homeRoleHeld,
                "dialerRoleAvailability" to dialerRoleAvailability,
                "smsRoleAvailability" to smsRoleAvailability
            ),
            "sensors" to mapOf(
                "cameraHardware" to packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY),
                "microphoneHardware" to packageManager.hasSystemFeature(PackageManager.FEATURE_MICROPHONE),
                "telephonyHardware" to packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY),
                "bluetoothHardware" to packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH),
                "hardwarePresenceOnly" to true
            ),
            "oem" to mapOf(
                "adapterId" to oem["adapterId"],
                "manufacturer" to oem["manufacturer"],
                "brand" to oem["brand"],
                "xiaomiFamily" to oem["xiaomiFamily"],
                "autostartManagement" to oem["autostartManagement"]
            ),
            "constraints" to mapOf(
                "normalOperationRequiresDesktop" to false,
                "rootRequired" to false,
                "bootloaderUnlockRequired" to false,
                "hiddenOemApiRequired" to false,
                "protectedAppAccessPolicy" to "deny_private_app_data_and_credentials",
                "developmentBridgePolicy" to "optional_not_trust_dependency"
            )
        )
    }
}
