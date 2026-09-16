package com.banataosystems.pandora_mobile

import android.content.Context

internal class PandoraProvisioningBootstrap(
    private val context: Context,
    private val oemAdapter: PandoraAndroidOemAdapter
) {
    fun snapshot(
        deviceOwnerProvisioned: Boolean,
        homeRoleHeld: Boolean
    ): Map<String, Any?> {
        val oem = oemAdapter.reliabilityState()
        val packageInstalled = try {
            context.packageManager.getApplicationInfo(context.packageName, 0)
            true
        } catch (_: Exception) {
            false
        }

        return mapOf(
            "schemaVersion" to "1.0.0",
            "platform" to "android",
            "runtimeLocation" to "on_device",
            "enrollmentMode" to "self_service_app_v1",
            "readiness" to if (packageInstalled) "ready_for_on_device_enrollment" else "blocked",
            "normalOperationRequiresDesktop" to false,
            "adbRequiredForNormalOperation" to false,
            "developmentBridgePolicy" to "optional_recovery_only",
            "rootRequired" to false,
            "bootloaderUnlockRequired" to false,
            "deviceOwnerProvisioned" to deviceOwnerProvisioned,
            "deviceOwnerRequiredForNormalOperation" to false,
            "homeRoleHeld" to homeRoleHeld,
            "protectedAppReauthenticationRequired" to true,
            "protectedAppAccessPolicy" to "deny_private_app_data_and_credentials",
            "setupSteps" to listOf(
                step(
                    "app_installation",
                    "installer",
                    if (packageInstalled) "complete" else "blocked",
                    true
                ),
                step(
                    "in_app_authentication",
                    "user",
                    "session_scoped_user_action",
                    true
                ),
                step(
                    "android_roles_and_permissions",
                    "user",
                    "capability_scoped_on_demand",
                    false
                ),
                step(
                    "oem_background_reliability",
                    "user",
                    if (oem["autostartManagement"] == "manual_oem_control") {
                        "optional_manual_oem_control"
                    } else {
                        "optional_if_needed"
                    },
                    false
                )
            ),
            "recoveryPaths" to listOf(
                recovery("android_settings", "user"),
                recovery("app_details", "user"),
                recovery("battery_optimization_settings", "user"),
                recovery("adb_development_bridge", "development_only")
            )
        )
    }

    private fun step(
        id: String,
        authority: String,
        state: String,
        normalOperationDependency: Boolean
    ): Map<String, Any?> = mapOf(
        "id" to id,
        "authority" to authority,
        "state" to state,
        "normalOperationDependency" to normalOperationDependency
    )
    private fun recovery(
        id: String,
        authority: String
    ): Map<String, Any?> = mapOf(
        "id" to id,
        "authority" to authority,
        "normalOperationDependency" to false
    )
}
