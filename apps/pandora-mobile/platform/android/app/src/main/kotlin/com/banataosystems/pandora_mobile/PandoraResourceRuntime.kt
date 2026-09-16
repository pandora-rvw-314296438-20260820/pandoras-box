package com.banataosystems.pandora_mobile

import android.Manifest
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.os.StatFs
import android.os.SystemClock
import android.os.health.SystemHealthManager

internal class PandoraResourceRuntime(
    private val context: Context
) {
    companion object {
        const val MIN_BENCHMARK_DURATION_MS = 25
        const val MAX_BENCHMARK_DURATION_MS = 100
        private const val DEFAULT_BENCHMARK_DURATION_MS = 40
    }

    fun snapshot(): Map<String, Any?> = mapOf(
        "schemaVersion" to "1.0.0",
        "capturedAtElapsedRealtimeMs" to SystemClock.elapsedRealtime(),
        "normalOperationRequiresDesktop" to false,
        "rootRequired" to false,
        "arbitraryCommandAccepted" to false,
        "cpu" to cpuState(),
        "gpu" to gpuState(),
        "memory" to memoryState(),
        "storage" to storageState(),
        "battery" to batteryState(),
        "thermal" to thermalState(),
        "process" to processState(),
        "network" to networkState()
    )

    fun runBenchmark(durationMs: Int? = null): Map<String, Any?> {
        val requestedDurationMs = durationMs ?: DEFAULT_BENCHMARK_DURATION_MS
        require(requestedDurationMs in MIN_BENCHMARK_DURATION_MS..MAX_BENCHMARK_DURATION_MS) {
            "durationMs must be between $MIN_BENCHMARK_DURATION_MS and $MAX_BENCHMARK_DURATION_MS."
        }

        val beforeThermal = currentThermalStatus()
        val startCpuMs = SystemClock.currentThreadTimeMillis()
        val startedNs = SystemClock.elapsedRealtimeNanos()
        val deadlineNs = startedNs + requestedDurationMs * 1_000_000L
        var iterations = 0L
        var checksum = 0L
        while (SystemClock.elapsedRealtimeNanos() < deadlineNs) {
            checksum = checksum xor ((iterations * 1_664_525L + 1_013_904_223L) and 0xFFFFFFFFL)
            iterations += 1L
        }
        val finishedNs = SystemClock.elapsedRealtimeNanos()
        val afterCpuMs = SystemClock.currentThreadTimeMillis()
        val afterThermal = currentThermalStatus()

        return mapOf(
            "schemaVersion" to "1.0.0",
            "kind" to "cpu_integer_mix_v1",
            "requestedDurationMs" to requestedDurationMs,
            "wallDurationMs" to ((finishedNs - startedNs) / 1_000_000.0),
            "cpuTimeMs" to (afterCpuMs - startCpuMs).coerceAtLeast(0L),
            "cpuTimeScope" to "benchmark_worker_thread",
            "iterations" to iterations,
            "checksum" to checksum,
            "thermalStatusBefore" to beforeThermal,
            "thermalStatusAfter" to afterThermal,
            "persistentMutation" to false,
            "arbitraryCommandAccepted" to false,
            "normalOperationRequiresDesktop" to false,
            "rootRequired" to false
        )
    }

    private fun cpuState(): Map<String, Any?> {
        val logicalProcessors = Runtime.getRuntime().availableProcessors().coerceAtLeast(1)
        val headroom = performanceHeadroom(cpu = true)
        return mapOf(
            "logicalProcessors" to logicalProcessors,
            "headroomSupported" to headroom.first,
            "headroomPercent" to headroom.second,
            "headroomMinIntervalMs" to headroom.third
        )
    }

    private fun gpuState(): Map<String, Any?> {
        val headroom = performanceHeadroom(cpu = false)
        return mapOf(
            "headroomSupported" to headroom.first,
            "headroomPercent" to headroom.second,
            "headroomMinIntervalMs" to headroom.third
        )
    }

    private data class HeadroomState(
        val first: Boolean,
        val second: Double?,
        val third: Long?
    )

    private fun performanceHeadroom(cpu: Boolean): HeadroomState {
        if (Build.VERSION.SDK_INT < 36) return HeadroomState(false, null, null)
        val manager = context.getSystemService(SystemHealthManager::class.java)
            ?: return HeadroomState(false, null, null)
        return try {
            val value = if (cpu) {
                manager.getCpuHeadroom(null)
            } else {
                manager.getGpuHeadroom(null)
            }
            val interval = if (cpu) {
                manager.cpuHeadroomMinIntervalMillis
            } else {
                manager.gpuHeadroomMinIntervalMillis
            }
            HeadroomState(true, finiteOrNull(value), interval)
        } catch (_: UnsupportedOperationException) {
            HeadroomState(false, null, null)
        } catch (_: SecurityException) {
            HeadroomState(false, null, null)
        } catch (_: IllegalArgumentException) {
            HeadroomState(false, null, null)
        } catch (_: IllegalStateException) {
            HeadroomState(false, null, null)
        }
    }

    private fun memoryState(): Map<String, Any?> {
        val manager = context.getSystemService(ActivityManager::class.java)
        val memory = ActivityManager.MemoryInfo()
        if (manager != null) manager.getMemoryInfo(memory)
        return mapOf(
            "totalBytes" to if (manager != null) memory.totalMem else null,
            "availableBytes" to if (manager != null) memory.availMem else null,
            "thresholdBytes" to if (manager != null) memory.threshold else null,
            "lowMemory" to if (manager != null) memory.lowMemory else null
        )
    }

    private fun processState(): Map<String, Any?> {
        val manager = context.getSystemService(ActivityManager::class.java)
        val processMemory = manager
            ?.getProcessMemoryInfo(intArrayOf(Process.myPid()))
            ?.firstOrNull()
        return mapOf(
            "pid" to Process.myPid(),
            "totalPssBytes" to processMemory?.let { it.totalPss.toLong() * 1024L },
            "javaHeapAllocatedBytes" to (
                Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory()
                ).coerceAtLeast(0L),
            "memoryClassMb" to manager?.memoryClass,
            "largeMemoryClassMb" to manager?.largeMemoryClass
        )
    }

    private fun storageState(): Map<String, Any?> {
        val stats = StatFs(context.filesDir.absolutePath)
        return mapOf(
            "scope" to "app_data_filesystem",
            "totalBytes" to stats.totalBytes,
            "availableBytes" to stats.availableBytes
        )
    }

    private fun batteryState(): Map<String, Any?> {
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        if (intent == null) {
            return mapOf(
                "available" to false,
                "levelPercent" to null,
                "charging" to null,
                "plugged" to "unknown",
                "temperatureCelsius" to null
            )
        }
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
        val temperatureTenths = intent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
        val percent = if (level >= 0 && scale > 0) level * 100.0 / scale else null
        val temperature = if (temperatureTenths != Int.MIN_VALUE) {
            temperatureTenths / 10.0
        } else {
            null
        }
        return mapOf(
            "available" to true,
            "levelPercent" to percent,
            "charging" to (
                status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL
                ),
            "plugged" to when (plugged) {
                BatteryManager.BATTERY_PLUGGED_AC -> "ac"
                BatteryManager.BATTERY_PLUGGED_USB -> "usb"
                BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"
                0 -> "battery"
                else -> "other"
            },
            "temperatureCelsius" to temperature
        )
    }

    private fun thermalState(): Map<String, Any?> {
        val manager = context.getSystemService(PowerManager::class.java)
        val status = currentThermalStatus(manager)
        var headroomSupported = false
        val headroom = if (manager != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                headroomSupported = true
                finiteOrNull(manager.getThermalHeadroom(0))
            } catch (_: UnsupportedOperationException) {
                headroomSupported = false
                null
            } catch (_: IllegalStateException) {
                headroomSupported = false
                null
            }
        } else {
            null
        }
        return mapOf(
            "status" to status,
            "headroomSupported" to headroomSupported,
            "headroom" to headroom
        )
    }

    private fun currentThermalStatus(manager: PowerManager? = context.getSystemService(PowerManager::class.java)): String {
        if (manager == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "unsupported"
        return when (manager.currentThermalStatus) {
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

    private fun networkState(): Map<String, Any?> {
        val permissionGranted = context.packageManager.checkPermission(
            Manifest.permission.ACCESS_NETWORK_STATE,
            context.packageName
        ) == PackageManager.PERMISSION_GRANTED
        if (!permissionGranted) {
            return mapOf(
                "permissionGranted" to false,
                "available" to false,
                "validated" to null,
                "metered" to null,
                "transports" to emptyList<String>(),
                "estimatedDownstreamKbps" to null,
                "estimatedUpstreamKbps" to null
            )
        }

        val manager = context.getSystemService(ConnectivityManager::class.java)
        val network = manager?.activeNetwork
        val capabilities = if (network != null) manager.getNetworkCapabilities(network) else null
        if (manager == null || capabilities == null) {
            return mapOf(
                "permissionGranted" to true,
                "available" to false,
                "validated" to false,
                "metered" to manager?.isActiveNetworkMetered,
                "transports" to emptyList<String>(),
                "estimatedDownstreamKbps" to null,
                "estimatedUpstreamKbps" to null
            )
        }

        val transports = buildList {
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) add("wifi")
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) add("cellular")
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) add("ethernet")
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) add("vpn")
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH)) add("bluetooth")
        }
        return mapOf(
            "permissionGranted" to true,
            "available" to true,
            "internetCapability" to capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET),
            "validated" to capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED),
            "captivePortal" to capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL),
            "metered" to manager.isActiveNetworkMetered,
            "transports" to transports,
            "estimatedDownstreamKbps" to capabilities.linkDownstreamBandwidthKbps,
            "estimatedUpstreamKbps" to capabilities.linkUpstreamBandwidthKbps
        )
    }

    private fun finiteOrNull(value: Float): Double? =
        if (value.isFinite()) value.toDouble() else null
}
