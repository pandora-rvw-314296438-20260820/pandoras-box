package com.banataosystems.pandora_mobile

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

internal object PandoraConnectivityChannel {
    private const val channelName = "pandora/connectivity"
    private const val schemaVersion = "1.0.0"
    private val supportedSettingsTargets = setOf("internet", "wifi", "mobile", "bluetooth", "usb")

    fun install(context: Context, messenger: BinaryMessenger) {
        val appContext = context.applicationContext
        MethodChannel(messenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "getConnectivityState" -> result.success(connectivityState(appContext))
                "openConnectivitySettings" -> openConnectivitySettings(appContext, call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun connectivityState(context: Context): Map<String, Any?> {
        val manager = context.getSystemService(ConnectivityManager::class.java)
        val activeNetwork = manager?.activeNetwork
        val capabilities = activeNetwork?.let { manager.getNetworkCapabilities(it) }

        fun hasTransport(transport: Int): Boolean =
            capabilities?.hasTransport(transport) == true

        val usbTransport = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            hasTransport(NetworkCapabilities.TRANSPORT_USB)

        return linkedMapOf(
            "schemaVersion" to schemaVersion,
            "capturedAtElapsedRealtimeMs" to SystemClock.elapsedRealtime(),
            "connected" to (capabilities != null),
            "internetCapable" to (capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true),
            "validated" to (capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true),
            "captivePortal" to (capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL) == true),
            "metered" to (capabilities != null && manager?.isActiveNetworkMetered == true),
            "transports" to linkedMapOf(
                "wifi" to hasTransport(NetworkCapabilities.TRANSPORT_WIFI),
                "cellular" to hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR),
                "bluetooth" to hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH),
                "ethernet" to hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET),
                "vpn" to hasTransport(NetworkCapabilities.TRANSPORT_VPN),
                "usb" to usbTransport
            ),
            "userControlOnly" to true,
            "silentMutationAllowed" to false,
            "normalOperationRequiresDesktop" to false,
            "rootRequired" to false
        )
    }

    private fun openConnectivitySettings(
        context: Context,
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        val target = call.argument<String>("target")?.trim()?.lowercase(Locale.ROOT).orEmpty()
        if (target !in supportedSettingsTargets) {
            result.error("INVALID_CONNECTIVITY_TARGET", "Unsupported connectivity settings target.", null)
            return
        }

        val primary = settingsIntent(target)
        val intent = if (primary.resolveActivity(context.packageManager) != null) {
            primary
        } else {
            fallbackSettingsIntent(target)?.takeIf {
                it.resolveActivity(context.packageManager) != null
            }
        }
        if (intent == null) {
            result.error("CONNECTIVITY_SETTINGS_UNAVAILABLE", "No safe system connectivity settings surface is available.", null)
            return
        }

        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
            result.success(
                mapOf(
                    "schemaVersion" to schemaVersion,
                    "target" to target,
                    "opened" to true,
                    "userActionRequired" to true,
                    "silentMutation" to false
                )
            )
        } catch (_: ActivityNotFoundException) {
            result.error("CONNECTIVITY_SETTINGS_UNAVAILABLE", "No safe system connectivity settings surface is available.", null)
        } catch (_: SecurityException) {
            result.error("CONNECTIVITY_SETTINGS_DENIED", "Android denied access to connectivity settings.", null)
        }
    }

    private fun settingsIntent(target: String): Intent = when (target) {
        "internet" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            Intent(Settings.Panel.ACTION_INTERNET_CONNECTIVITY)
        } else {
            Intent(Settings.ACTION_WIRELESS_SETTINGS)
        }
        "wifi" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            Intent(Settings.Panel.ACTION_WIFI)
        } else {
            Intent(Settings.ACTION_WIFI_SETTINGS)
        }
        "mobile" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            Intent(Settings.Panel.ACTION_INTERNET_CONNECTIVITY)
        } else {
            Intent(Settings.ACTION_NETWORK_OPERATOR_SETTINGS)
        }
        "bluetooth" -> Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
        "usb" -> Intent(Settings.ACTION_WIRELESS_SETTINGS)
        else -> Intent(Settings.ACTION_WIRELESS_SETTINGS)
    }

    private fun fallbackSettingsIntent(target: String): Intent? = when (target) {
        "bluetooth" -> Intent(Settings.ACTION_SETTINGS)
        "internet", "wifi", "mobile", "usb" -> Intent(Settings.ACTION_WIRELESS_SETTINGS)
        else -> null
    }
}
