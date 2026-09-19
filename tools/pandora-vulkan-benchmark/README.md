# Pandora Vulkan Benchmark

Standalone Android benchmark used to verify whether the phone can actually
offload Qwen/llama.cpp inference to Vulkan.

It is intentionally separate from the production Pandora mobile app.

## Runtime

- ABI: arm64-v8a
- minSdk: 26
- compileSdk / targetSdk: 36
- llama.cpp upstream:
  `44be98f057e9f9902a8ee12630e181c7f8ec2953`
- Vulkan backend: `GGML_VULKAN=ON`

## Test procedure

1. Install the debug APK built by GitHub Actions.
2. Select the existing `Qwen3-4B-Instruct-2507-Q4_K_M.gguf`.
3. Run CPU (0 GPU layers).
4. Run Hybrid (18 GPU layers).
5. Run Vulkan (99 requested GPU layers / full offload where supported).
6. Compare the native llama-bench output.

Vulkan is considered proven only when the native backend probe exposes a
GPU/IGPU backend and llama-bench reports GPU execution/offload. Android
feature flags alone are not treated as proof.

The app does not collect stable device identifiers or upload the selected
model.
