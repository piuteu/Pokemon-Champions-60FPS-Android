#include <jni.h>
#include <android/log.h>

#include <dlfcn.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include <sys/syscall.h>
#include <unistd.h>

#if defined(__aarch64__)
static constexpr const char* kCompileArch = "aarch64";
#else
static constexpr const char* kCompileArch = "not-aarch64";
#endif

static long current_tid() {
    return static_cast<long>(syscall(SYS_gettid));
}

static void log_event(const char* event) {
    __android_log_print(
        ANDROID_LOG_INFO,
        "PCFPS",
        "%s pid=%ld tid=%ld compile_arch=%s",
        event,
        static_cast<long>(getpid()),
        current_tid(),
        kCompileArch);
}

static void log_message(int priority, const char* format, ...) {
    va_list arguments;
    va_start(arguments, format);
    __android_log_vprint(priority, "PCFPS", format, arguments);
    va_end(arguments);
}

struct MappingInfo {
    uintptr_t start;
    uintptr_t end;
    uintptr_t file_offset;
    char permissions[5];
    char path[512];
};

static bool parse_mapping(const char* line, MappingInfo* mapping) {
    unsigned long long start = 0;
    unsigned long long end = 0;
    unsigned long long file_offset = 0;
    char permissions[5] = {};

    if (line == nullptr || mapping == nullptr ||
        sscanf(line, "%llx-%llx %4s %llx", &start, &end, permissions, &file_offset) != 4) {
        return false;
    }

    mapping->start = static_cast<uintptr_t>(start);
    mapping->end = static_cast<uintptr_t>(end);
    mapping->file_offset = static_cast<uintptr_t>(file_offset);
    memcpy(mapping->permissions, permissions, sizeof(mapping->permissions));
    mapping->path[0] = '\0';

    const char* path = strchr(line, '/');
    if (path == nullptr) {
        path = strchr(line, '[');
    }
    if (path != nullptr) {
        strncpy(mapping->path, path, sizeof(mapping->path) - 1);
        mapping->path[sizeof(mapping->path) - 1] = '\0';
        const size_t length = strlen(mapping->path);
        if (length > 0 && mapping->path[length - 1] == '\n') {
            mapping->path[length - 1] = '\0';
        }
    }
    return true;
}

static bool find_mapping(uintptr_t address, const char* path_needle, MappingInfo* result) {
    FILE* maps = fopen("/proc/self/maps", "re");
    if (maps == nullptr) {
        return false;
    }

    char line[1024];
    bool found = false;
    while (fgets(line, sizeof(line), maps) != nullptr) {
        MappingInfo mapping = {};
        if (!parse_mapping(line, &mapping) || address < mapping.start || address >= mapping.end) {
            continue;
        }
        if (path_needle != nullptr && strstr(mapping.path, path_needle) == nullptr) {
            continue;
        }
        if (result != nullptr) {
            *result = mapping;
        }
        found = true;
        break;
    }
    fclose(maps);
    return found;
}

static uintptr_t find_module_base(const char* path_needle) {
    if (path_needle == nullptr) {
        return 0;
    }

    FILE* maps = fopen("/proc/self/maps", "re");
    if (maps == nullptr) {
        return 0;
    }

    char line[1024];
    uintptr_t base = 0;
    while (fgets(line, sizeof(line), maps) != nullptr) {
        MappingInfo mapping = {};
        if (!parse_mapping(line, &mapping)) {
            continue;
        }
        if (mapping.file_offset == 0 && strstr(mapping.path, path_needle) != nullptr) {
            base = mapping.start;
            break;
        }
    }
    fclose(maps);
    return base;
}

using TargetFrameRateIcall = void (*)(int32_t);
using AnimationFrameRateIcall = float (*)(void*);
using ResolveIcall = void* (*)(const char*);

static TargetFrameRateIcall g_original_target_frame_rate = nullptr;
static AnimationFrameRateIcall g_original_animation_frame_rate = nullptr;
static uintptr_t g_animation_libil2cpp_base = 0;

static constexpr uintptr_t kAdvanceTimeFrameRateReturnRva = 0x277D068;

static uintptr_t normalize_guest_pc(uintptr_t address) {
    return address & 0x0000FFFFFFFFFFFFULL;
}

static bool is_advance_time_frame_rate_call(uintptr_t caller) {
    const uintptr_t normalized_caller = normalize_guest_pc(caller);
    return g_animation_libil2cpp_base != 0 &&
        normalized_caller == g_animation_libil2cpp_base + kAdvanceTimeFrameRateReturnRva;
}

__attribute__((noinline)) static float hook_animation_get_frame_rate(void* clip) {
    if (g_original_animation_frame_rate == nullptr) {
        return 0.0f;
    }

    const float frame_rate = g_original_animation_frame_rate(clip);
    const uintptr_t caller = normalize_guest_pc(reinterpret_cast<uintptr_t>(__builtin_return_address(0)));
    if (!is_advance_time_frame_rate_call(caller)) {
        return frame_rate;
    }
    return frame_rate == 30.0f ? 60.0f : frame_rate;
}

static bool install_animation_cache_hook(
    uintptr_t cache_address,
    void* resolved_target,
    void* replacement,
    AnimationFrameRateIcall* original_target) {
    *original_target = nullptr;

    MappingInfo cache_mapping = {};
    const bool mapped = cache_address != 0 && find_mapping(cache_address, nullptr, &cache_mapping);
    const bool readable = mapped && cache_mapping.permissions[0] == 'r';
    const bool writable = mapped && cache_mapping.permissions[1] == 'w';
    if (!readable || !writable) {
        log_message(
            ANDROID_LOG_ERROR,
            "ANIM_FRAMERATE_HOOK_NOT_INSTALLED cache_readable=%s cache_writable=%s",
            readable ? "yes" : "no",
            writable ? "yes" : "no");
        return false;
    }

    void* cache_value = *reinterpret_cast<void* volatile*>(cache_address);
    void* original = cache_value != nullptr ? cache_value : resolved_target;
    if (original == nullptr) {
        log_message(ANDROID_LOG_ERROR, "ANIM_FRAMERATE_HOOK_NOT_INSTALLED original_missing");
        return false;
    }
    if (cache_value != nullptr && resolved_target != nullptr && cache_value != resolved_target) {
        log_message(ANDROID_LOG_ERROR, "ANIM_FRAMERATE_HOOK_NOT_INSTALLED target_mismatch");
        return false;
    }

    *original_target = reinterpret_cast<AnimationFrameRateIcall>(original);
    *reinterpret_cast<void* volatile*>(cache_address) = replacement;
    const void* cache_after = *reinterpret_cast<void* volatile*>(cache_address);
    if (cache_after != replacement) {
        log_message(ANDROID_LOG_ERROR, "ANIM_FRAMERATE_HOOK_NOT_INSTALLED cache_write_failed");
        *original_target = nullptr;
        return false;
    }
    return true;
}

__attribute__((noinline)) static void hook_target_frame_rate(int32_t requested) {
    if (g_original_target_frame_rate == nullptr) {
        return;
    }
    const int32_t effective = (requested == 30 || requested == -1) ? 60 : requested;
    g_original_target_frame_rate(effective);
}

static void resolve_and_install_hook() {
    const uintptr_t libil2cpp_base = find_module_base("/libil2cpp.so");
    if (libil2cpp_base == 0) {
        log_message(ANDROID_LOG_ERROR, "HOOK_NOT_INSTALLED libil2cpp_missing");
        return;
    }

    void* handle = dlopen("libil2cpp.so", RTLD_NOW);
    if (handle == nullptr) {
        const char* error = dlerror();
        log_message(
            ANDROID_LOG_ERROR,
            "HOOK_NOT_INSTALLED dlopen_libil2cpp_failed reason=%s",
            error != nullptr ? error : "unknown");
        return;
    }

    (void)dlerror();
    void* resolver_address = dlsym(handle, "il2cpp_resolve_icall");
    if (resolver_address == nullptr) {
        const char* error = dlerror();
        log_message(
            ANDROID_LOG_ERROR,
            "HOOK_NOT_INSTALLED resolver_missing reason=%s",
            error != nullptr ? error : "unknown");
        dlclose(handle);
        return;
    }

    const ResolveIcall resolve_icall = reinterpret_cast<ResolveIcall>(resolver_address);
    const char* target_name = "UnityEngine.Application::set_targetFrameRate(System.Int32)";
    void* resolved_target = resolve_icall(target_name);
    MappingInfo target_mapping = {};
    const bool target_in_unity = resolved_target != nullptr &&
        find_mapping(reinterpret_cast<uintptr_t>(resolved_target), "/libunity.so", &target_mapping);
    if (!target_in_unity) {
        log_message(ANDROID_LOG_ERROR, "HOOK_NOT_INSTALLED target_not_in_libunity");
        dlclose(handle);
        return;
    }

    const uintptr_t cache_address = libil2cpp_base + 0x5612250;
    MappingInfo cache_mapping = {};
    const bool cache_mapped = find_mapping(cache_address, nullptr, &cache_mapping);
    const bool cache_readable = cache_mapped && cache_mapping.permissions[0] == 'r';
    const bool cache_writable = cache_mapped && cache_mapping.permissions[1] == 'w';
    if (!cache_readable || !cache_writable) {
        log_message(
            ANDROID_LOG_ERROR,
            "HOOK_NOT_INSTALLED icall_cache_readable=%s icall_cache_writable=%s",
            cache_readable ? "yes" : "no",
            cache_writable ? "yes" : "no");
        dlclose(handle);
        return;
    }

    void* cache_value = *reinterpret_cast<void* volatile*>(cache_address);
    if (cache_value == nullptr || cache_value != resolved_target) {
        log_message(ANDROID_LOG_ERROR, "HOOK_NOT_INSTALLED icall_cache_target_mismatch");
        dlclose(handle);
        return;
    }

    g_original_target_frame_rate = reinterpret_cast<TargetFrameRateIcall>(cache_value);
    *reinterpret_cast<void* volatile*>(cache_address) = reinterpret_cast<void*>(&hook_target_frame_rate);
    if (*reinterpret_cast<void* volatile*>(cache_address) != reinterpret_cast<void*>(&hook_target_frame_rate)) {
        log_message(ANDROID_LOG_ERROR, "HOOK_NOT_INSTALLED icall_cache_write_failed");
        g_original_target_frame_rate = nullptr;
        dlclose(handle);
        return;
    }
    log_event("HOOK_INSTALL");

    g_animation_libil2cpp_base = libil2cpp_base;
    const char* frame_rate_name = "UnityEngine.AnimationClip::get_frameRate_Injected(System.IntPtr)";
    void* resolved_frame_rate = resolve_icall(frame_rate_name);
    const uintptr_t frame_rate_cache = libil2cpp_base + 0x5611A78;
    if (install_animation_cache_hook(
            frame_rate_cache,
            resolved_frame_rate,
            reinterpret_cast<void*>(&hook_animation_get_frame_rate),
            &g_original_animation_frame_rate)) {
        log_event("ANIMATION_FRAMERATE_HOOK_INSTALLED");
    }

    log_event("HOOK_INITIAL_SET effective=60");
    g_original_target_frame_rate(60);
    dlclose(handle);
}

__attribute__((constructor)) static void pc_fps_runtime_constructor() {
    log_event("ARM64_GUEST_CONSTRUCTOR");
}

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM*, void*) {
    log_event("ARM64_GUEST_JNI_ONLOAD");
    log_event("ARM64_GUEST_BEFORE_RESOLVE");
    resolve_and_install_hook();
    log_event("ARM64_GUEST_AFTER_RESOLVE");
    return JNI_VERSION_1_6;
}
