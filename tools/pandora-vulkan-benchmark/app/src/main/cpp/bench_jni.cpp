#include <jni.h>

#include <cstdio>
#include <fcntl.h>
#include <mutex>
#include <sstream>
#include <string>
#include <unistd.h>
#include <vector>

#include "ggml-backend.h"
#include "llama.h"

int llama_bench(int argc, char ** argv);

static std::mutex g_bench_mutex;

static std::string jstring_to_string(JNIEnv * env, jstring value) {
    if (value == nullptr) {
        return {};
    }

    const char * chars = env->GetStringUTFChars(value, nullptr);
    std::string result = chars ? chars : "";

    if (chars != nullptr) {
        env->ReleaseStringUTFChars(value, chars);
    }

    return result;
}

static std::string read_file(const std::string & path) {
    FILE * file = fopen(path.c_str(), "rb");
    if (file == nullptr) {
        return "Could not read benchmark output file.";
    }

    std::string output;
    char buffer[8192];
    size_t read = 0;

    while ((read = fread(buffer, 1, sizeof(buffer), file)) > 0) {
        output.append(buffer, read);
    }

    fclose(file);
    return output;
}

static const char * device_type_name(enum ggml_backend_dev_type type) {
    switch (type) {
        case GGML_BACKEND_DEVICE_TYPE_CPU:
            return "CPU";
        case GGML_BACKEND_DEVICE_TYPE_GPU:
            return "GPU";
        case GGML_BACKEND_DEVICE_TYPE_IGPU:
            return "IGPU";
        case GGML_BACKEND_DEVICE_TYPE_ACCEL:
            return "ACCEL";
        default:
            return "UNKNOWN";
    }
}

extern "C"
JNIEXPORT jstring JNICALL
Java_com_banataosystems_pandoravulkanbenchmark_MainActivity_nativeBackendSummary(
        JNIEnv * env,
        jobject) {
    std::ostringstream summary;

    ggml_backend_load_all();
    llama_backend_init();

    const size_t count = ggml_backend_dev_count();
    summary << "Device count: " << count << "\n";

    for (size_t i = 0; i < count; ++i) {
        ggml_backend_dev_t device = ggml_backend_dev_get(i);
        const char * name = ggml_backend_dev_name(device);
        const char * description = ggml_backend_dev_description(device);
        const enum ggml_backend_dev_type type = ggml_backend_dev_type(device);

        size_t free_memory = 0;
        size_t total_memory = 0;
        ggml_backend_dev_memory(device, &free_memory, &total_memory);

        summary
            << "[" << i << "] "
            << (name ? name : "?")
            << " | " << (description ? description : "?")
            << " | type=" << device_type_name(type)
            << " | free=" << free_memory
            << " | total=" << total_memory
            << "\n";
    }

    llama_backend_free();

    return env->NewStringUTF(summary.str().c_str());
}

extern "C"
JNIEXPORT jstring JNICALL
Java_com_banataosystems_pandoravulkanbenchmark_MainActivity_runBench(
        JNIEnv * env,
        jobject,
        jstring model_path_java,
        jint gpu_layers,
        jstring output_path_java) {
    std::lock_guard<std::mutex> lock(g_bench_mutex);

    const std::string model_path =
        jstring_to_string(env, model_path_java);
    const std::string output_path =
        jstring_to_string(env, output_path_java);

    int output_fd = open(
        output_path.c_str(),
        O_CREAT | O_TRUNC | O_WRONLY,
        0600);

    if (output_fd < 0) {
        return env->NewStringUTF("Failed to create native benchmark output.");
    }

    const int saved_stdout = dup(STDOUT_FILENO);
    const int saved_stderr = dup(STDERR_FILENO);

    fflush(stdout);
    fflush(stderr);

    dup2(output_fd, STDOUT_FILENO);
    dup2(output_fd, STDERR_FILENO);
    close(output_fd);

    std::vector<std::string> args = {
        "llama-bench",
        "-m", model_path,
        "-p", "512",
        "-n", "128",
        "-r", "3",
        "-ngl", std::to_string(static_cast<int>(gpu_layers))
    };

    std::vector<char *> argv;
    argv.reserve(args.size());

    for (std::string & arg : args) {
        argv.push_back(arg.data());
    }

    int exit_code = -999;

    try {
        exit_code = llama_bench(
            static_cast<int>(argv.size()),
            argv.data());
    } catch (const std::exception & e) {
        fprintf(stderr, "\nJNI wrapper exception: %s\n", e.what());
        exit_code = -998;
    } catch (...) {
        fprintf(stderr, "\nJNI wrapper unknown native exception\n");
        exit_code = -997;
    }

    fflush(stdout);
    fflush(stderr);

    dup2(saved_stdout, STDOUT_FILENO);
    dup2(saved_stderr, STDERR_FILENO);

    close(saved_stdout);
    close(saved_stderr);

    std::ostringstream result;
    result
        << "llama-bench exit code: " << exit_code << "\n"
        << "Model path: " << model_path << "\n"
        << "Requested n_gpu_layers: " << gpu_layers << "\n\n"
        << read_file(output_path);

    return env->NewStringUTF(result.str().c_str());
}
