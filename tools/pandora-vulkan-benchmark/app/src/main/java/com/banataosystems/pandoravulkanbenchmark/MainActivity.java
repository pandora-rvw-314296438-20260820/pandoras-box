package com.banataosystems.pandoravulkanbenchmark;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.FeatureInfo;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.File;
import java.io.IOException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class MainActivity extends Activity {
    static {
        System.loadLibrary("pandora_bench");
    }

    private static final int PICK_MODEL = 1001;

    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private TextView output;
    private TextView modelStatus;
    private TextView nativeStatus;
    private ParcelFileDescriptor modelFd;
    private Uri modelUri;

    private native String runBench(String modelPath, int gpuLayers, String outputPath);
    private native String nativeBackendSummary();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(32, 28, 32, 28);

        TextView title = new TextView(this);
        title.setText("Pandora Vulkan Benchmark");
        title.setTextSize(24f);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        root.addView(title);

        TextView subtitle = new TextView(this);
        subtitle.setText(
                "Standalone local-AI GPU offload verifier\n" +
                "llama.cpp: 44be98f057e9f9902a8ee12630e181c7f8ec2953");
        subtitle.setTextSize(14f);
        subtitle.setPadding(0, 8, 0, 18);
        root.addView(subtitle);

        TextView device = new TextView(this);
        device.setText(buildDeviceSummary());
        device.setTextIsSelectable(true);
        root.addView(device);

        nativeStatus = new TextView(this);
        nativeStatus.setText("\nNative backend probe:\n" + safeBackendSummary());
        nativeStatus.setTextIsSelectable(true);
        root.addView(nativeStatus);

        modelStatus = new TextView(this);
        modelStatus.setText("\nModel: none selected");
        modelStatus.setTextIsSelectable(true);
        root.addView(modelStatus);

        Button choose = new Button(this);
        choose.setText("Select GGUF model");
        choose.setOnClickListener(v -> pickModel());
        root.addView(choose);

        Button refresh = new Button(this);
        refresh.setText("Refresh native backend probe");
        refresh.setOnClickListener(v ->
                nativeStatus.setText("\nNative backend probe:\n" + safeBackendSummary()));
        root.addView(refresh);

        Button cpu = new Button(this);
        cpu.setText("Run CPU — 0 GPU layers");
        cpu.setOnClickListener(v -> run(0, "CPU"));
        root.addView(cpu);

        Button hybrid = new Button(this);
        hybrid.setText("Run HYBRID — 18 GPU layers");
        hybrid.setOnClickListener(v -> run(18, "HYBRID"));
        root.addView(hybrid);

        Button gpu = new Button(this);
        gpu.setText("Run VULKAN — all GPU layers");
        gpu.setOnClickListener(v -> run(99, "VULKAN"));
        root.addView(gpu);

        output = new TextView(this);
        output.setTextSize(12f);
        output.setTypeface(Typeface.MONOSPACE);
        output.setTextIsSelectable(true);
        output.setPadding(0, 22, 0, 32);
        output.setText(
                "Select Qwen3-4B-Instruct-2507-Q4_K_M.gguf.\n\n" +
                "Run CPU first, then HYBRID, then VULKAN.\n\n" +
                "Truth rule: Vulkan is proven only when the native backend probe " +
                "shows a GPU/IGPU Vulkan device and llama-bench reports non-zero " +
                "GPU-layer offload. Android merely advertising Vulkan is not proof.");
        root.addView(output);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(root);
        setContentView(scroll);
    }

    private String safeBackendSummary() {
        try {
            return nativeBackendSummary();
        } catch (Throwable t) {
            return "Native backend probe failed: " + t;
        }
    }

    private String buildDeviceSummary() {
        PackageManager pm = getPackageManager();
        boolean vk = pm.hasSystemFeature(PackageManager.FEATURE_VULKAN_HARDWARE_LEVEL);
        int version = 0;
        int level = 0;
        FeatureInfo[] infos = pm.getSystemAvailableFeatures();
        if (infos != null) {
            for (FeatureInfo f : infos) {
                if (PackageManager.FEATURE_VULKAN_HARDWARE_VERSION.equals(f.name)) {
                    version = f.version;
                } else if (PackageManager.FEATURE_VULKAN_HARDWARE_LEVEL.equals(f.name)) {
                    level = f.version;
                }
            }
        }

        return "Android SDK: " + android.os.Build.VERSION.SDK_INT +
                "\nABI: " + android.os.Build.SUPPORTED_ABIS[0] +
                "\nAndroid reports Vulkan feature: " + vk +
                "\nVulkan feature version raw: " + version +
                "\nVulkan hardware level raw: " + level +
                "\nStable device identifiers collected: NO";
    }

    private void pickModel() {
        Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        i.addCategory(Intent.CATEGORY_OPENABLE);
        i.setType("*/*");
        i.addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION |
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        startActivityForResult(i, PICK_MODEL);
    }

    @Override
    @SuppressWarnings("deprecation")
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != PICK_MODEL ||
                resultCode != RESULT_OK ||
                data == null ||
                data.getData() == null) {
            return;
        }

        closeModelFd();
        modelUri = data.getData();

        try {
            getContentResolver().takePersistableUriPermission(
                    modelUri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION);
        } catch (Exception ignored) {
        }

        try {
            modelFd = getContentResolver().openFileDescriptor(modelUri, "r");
            if (modelFd == null) {
                throw new IOException("openFileDescriptor returned null");
            }

            long size = modelFd.getStatSize();
            modelStatus.setText(
                    "\nModel URI: " + modelUri +
                    "\nSize: " + size + " bytes" +
                    "\nFD path: /proc/self/fd/" + modelFd.getFd());
        } catch (Exception e) {
            modelStatus.setText("\nFailed to open model: " + e);
            closeModelFd();
        }
    }

    private void run(int gpuLayers, String label) {
        if (modelFd == null) {
            Toast.makeText(this, "Select a GGUF model first", Toast.LENGTH_SHORT).show();
            return;
        }

        final String modelPath = "/proc/self/fd/" + modelFd.getFd();
        final File out = new File(
                getCacheDir(),
                "llama-bench-" + System.currentTimeMillis() + ".txt");

        output.setText(
                "Running " + label + "...\n" +
                "GPU layers requested: " + gpuLayers + "\n" +
                "This may take several minutes. Keep the app open.");

        executor.execute(() -> {
            final String result;
            try {
                result = runBench(modelPath, gpuLayers, out.getAbsolutePath());
            } catch (Throwable t) {
                runOnUiThread(() ->
                        output.setText("Native benchmark failed: " + t));
                return;
            }

            runOnUiThread(() ->
                    output.setText(
                            "Requested mode: " + label +
                            "\nRequested GPU layers: " + gpuLayers +
                            "\n\n" + result));
        });
    }

    private void closeModelFd() {
        if (modelFd != null) {
            try {
                modelFd.close();
            } catch (IOException ignored) {
            }
            modelFd = null;
        }
    }

    @Override
    protected void onDestroy() {
        closeModelFd();
        executor.shutdownNow();
        super.onDestroy();
    }
}
