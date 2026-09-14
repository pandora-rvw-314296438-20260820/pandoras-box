#!/usr/bin/env python3
"""M4-009 source-boundary tests for governed mobile resource introspection."""

from __future__ import annotations

import unittest
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
_RESOURCE = (
    _ROOT
    / "platform"
    / "android"
    / "app"
    / "src"
    / "main"
    / "kotlin"
    / "com"
    / "banataosystems"
    / "pandora_mobile"
    / "PandoraResourceRuntime.kt"
)
_CHANNEL = (
    _ROOT
    / "platform"
    / "android"
    / "app"
    / "src"
    / "main"
    / "kotlin"
    / "com"
    / "banataosystems"
    / "pandora_mobile"
    / "PandoraDeviceAgentChannel.kt"
)
_DART = _ROOT / "lib" / "core" / "device" / "pandora_resource_runtime.dart"
_MANIFEST_TOOL = _ROOT / "tool" / "configure_validation_android.py"


class ResourceRuntimeContractTest(unittest.TestCase):
    def test_uses_public_resource_apis_without_deep_hardware_authority(self) -> None:
        source = _RESOURCE.read_text(encoding="utf-8")

        for required in (
            "SystemHealthManager",
            "getCpuHeadroom(null)",
            "getGpuHeadroom(null)",
            "ActivityManager.MemoryInfo",
            "getProcessMemoryInfo",
            "StatFs",
            "BatteryManager",
            "getThermalHeadroom(0)",
            "currentThermalStatus",
            "ConnectivityManager",
            "NET_CAPABILITY_VALIDATED",
        ):
            self.assertIn(required, source)

        for forbidden in (
            "HardwarePropertiesManager",
            "Runtime.getRuntime().exec",
            "ProcessBuilder",
            "Settings.Secure.ANDROID_ID",
            "Build.SERIAL",
            "getConnectionInfo",
            "SSID",
            "BSSID",
            "NetworkInterface",
        ):
            self.assertNotIn(forbidden, source)

    def test_benchmark_is_bounded_and_command_free(self) -> None:
        source = _RESOURCE.read_text(encoding="utf-8")

        self.assertIn("MIN_BENCHMARK_DURATION_MS = 25", source)
        self.assertIn("MAX_BENCHMARK_DURATION_MS = 100", source)
        self.assertIn('"persistentMutation" to false', source)
        self.assertIn('"arbitraryCommandAccepted" to false', source)
        self.assertNotIn("command:", source)
        self.assertNotIn('call.argument<String>("command")', source)

    def test_device_agent_exposes_only_named_resource_methods(self) -> None:
        source = _CHANNEL.read_text(encoding="utf-8")

        self.assertIn('"getResourceSnapshot"', source)
        self.assertIn('"runResourceBenchmark"', source)
        self.assertIn("PandoraResourceRuntime(context)", source)
        self.assertIn('"resource.introspection"', source)
        self.assertIn('"available"', source)
        self.assertIn('"connectivity.state"', source)
        self.assertIn(
            '"Connectivity capability belongs to M4-007."',
            source,
        )

    def test_dart_contract_rejects_identifiers_and_trust_weakening(self) -> None:
        source = _DART.read_text(encoding="utf-8")

        for required in (
            "PandoraResourceSnapshot",
            "PandoraResourceBenchmarkRequest",
            "PandoraResourceBenchmarkResult",
            "normalOperationRequiresDesktop",
            "arbitraryCommandAccepted",
            "ssid",
            "bssid",
            "androidId",
            "serial",
        ):
            self.assertIn(required, source)

        self.assertIn("maxDurationMs = 100", source)
        self.assertIn("'getResourceSnapshot'", source)
        self.assertIn("'runResourceBenchmark'", source)

    def test_network_read_permission_is_bounded(self) -> None:
        manifest_tool = _MANIFEST_TOOL.read_text(encoding="utf-8")

        self.assertIn("android.permission.ACCESS_NETWORK_STATE", manifest_tool)
        for forbidden in (
            "android.permission.ACCESS_FINE_LOCATION",
            "android.permission.ACCESS_COARSE_LOCATION",
            "android.permission.BLUETOOTH_SCAN",
            "android.permission.BLUETOOTH_CONNECT",
            "android.permission.READ_PHONE_STATE",
        ):
            self.assertNotIn(forbidden, manifest_tool)


    def test_resource_work_runs_off_main_looper_and_completes_on_main(self) -> None:
        source = _CHANNEL.read_text(encoding="utf-8")

        for required in (
            "Executors.newSingleThreadExecutor",
            'Thread(runnable, "pandora-resource-runtime")',
            "Handler(Looper.getMainLooper())",
            "resourceExecutor.execute",
            "mainHandler.post",
            '"getResourceSnapshot" -> runResourceSnapshot(result)',
        ):
            self.assertIn(required, source)

        self.assertNotIn(
            '"getResourceSnapshot" -> result.success(resourceRuntime.snapshot())',
            source,
        )
if __name__ == "__main__":
    unittest.main()
