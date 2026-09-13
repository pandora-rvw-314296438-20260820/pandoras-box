package com.banataosystems.pandora_mobile

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import java.util.Locale

internal class PandoraAndroidOemAdapter(
    private val context: Context
) {
    fun reliabilityState(): Map<String, Any?> {
        val xiaomiFamily = isXiaomiFamily()
        val backgroundRestrictionSupported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
        val backgroundRestricted = if (backgroundRestrictionSupported) {
            context.getSystemService(ActivityManager::class.java)?.isBackgroundRestricted
        } else {
            null
        }
        val batteryOptimizationStateSupported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
        val ignoringBatteryOptimizations = if (batteryOptimizationStateSupported) {
            context.getSystemService(PowerManager::class.java)
                ?.isIgnoringBatteryOptimizations(context.packageName)
        } else {
            null
        }

        return mapOf(
            "schemaVersion" to "1.0.0",
            "adapterId" to if (xiaomiFamily) "xiaomi_public_v1" else "android_generic_public_v1",
            "manufacturer" to Build.MANUFACTURER.ifBlank { "unknown" },
            "brand" to Build.BRAND.ifBlank { "unknown" },
            "xiaomiFamily" to xiaomiFamily,
            "backgroundRestrictionSupported" to backgroundRestrictionSupported,
            "backgroundRestricted" to backgroundRestricted,
            "batteryOptimizationStateSupported" to batteryOptimizationStateSupported,
            "ignoringBatteryOptimizations" to ignoringBatteryOptimizations,
            "autostartManagement" to if (xiaomiFamily) {
                "manual_oem_control"
            } else {
                "public_api_unavailable"
            },
            "appDetailsSurfaceAvailable" to canOpen(appDetailsIntent()),
            "batteryOptimizationSurfaceAvailable" to canOpen(batteryOptimizationIntent()),
            "normalOperationRequiresDesktop" to false,
            "rootRequired" to false,
            "bootloaderUnlockRequired" to false,
            "hiddenOemApiRequired" to false
        )
    }

    fun openAppDetails(): Boolean = open(appDetailsIntent())

    fun openBatteryOptimizationSettings(): Boolean = open(batteryOptimizationIntent())

    fun isXiaomiFamily(): Boolean {
        val manufacturer = Build.MANUFACTURER.lowercase(Locale.ROOT)
        val brand = Build.BRAND.lowercase(Locale.ROOT)
        return manufacturer == "xiaomi" ||
            manufacturer == "redmi" ||
            manufacturer == "poco" ||
            brand == "xiaomi" ||
            brand == "redmi" ||
            brand == "poco"
    }

    private fun appDetailsIntent(): Intent = Intent(
        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.fromParts("package", context.packageName, null)
    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    private fun batteryOptimizationIntent(): Intent = Intent(
        Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    private fun canOpen(intent: Intent): Boolean =
        intent.resolveActivity(context.packageManager) != null

    private fun open(intent: Intent): Boolean {
        if (!canOpen(intent)) return false
        return try {
            context.startActivity(intent)
            true
        } catch (_: RuntimeException) {
            false
        }
    }
}
