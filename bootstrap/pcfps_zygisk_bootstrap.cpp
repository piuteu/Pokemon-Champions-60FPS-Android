#include <android/log.h>
#include <jni.h>

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "zygisk.hpp"

namespace {

constexpr const char* kTargetPackage = "jp.pokemon.pokemonchampions";
constexpr const char* kRequiredVersionName = "1.1.5";
constexpr jint kRequiredVersionCode = 3191;
constexpr const char* kPayloadRelativePath = "payload/libpcfps_runtime.so";
constexpr const char* kPayloadFileName = "libpcfps_runtime.so";
constexpr useconds_t kPollIntervalUs = 250000;
constexpr int kPollAttempts = 240;

static void log_message(int priority, const char* format, ...) {
    va_list arguments;
    va_start(arguments, format);
    __android_log_vprint(priority, "PCFPS-ZB", format, arguments);
    va_end(arguments);
}

static void clear_pending_exception(JNIEnv* env) {
    if (env != nullptr && env->ExceptionCheck()) {
        env->ExceptionClear();
    }
}

class ScopedFd final {
public:
    explicit ScopedFd(int fd) : fd_(fd) {}
    ~ScopedFd() {
        if (fd_ >= 0) {
            close(fd_);
        }
    }
    ScopedFd(const ScopedFd&) = delete;
    ScopedFd& operator=(const ScopedFd&) = delete;
    int get() const { return fd_; }

private:
    int fd_;
};

static uint32_t rotate_right(uint32_t value, unsigned amount) {
    return (value >> amount) | (value << (32 - amount));
}

class Sha256 final {
public:
    Sha256()
        : state_{
              0x6a09e667u,
              0xbb67ae85u,
              0x3c6ef372u,
              0xa54ff53au,
              0x510e527fu,
              0x9b05688cu,
              0x1f83d9abu,
              0x5be0cd19u},
          total_bytes_(0),
          buffered_bytes_(0) {}

    void update(const uint8_t* data, size_t length) {
        total_bytes_ += length;
        while (length != 0) {
            const size_t available = sizeof(buffer_) - buffered_bytes_;
            const size_t chunk = length < available ? length : available;
            memcpy(buffer_ + buffered_bytes_, data, chunk);
            buffered_bytes_ += chunk;
            data += chunk;
            length -= chunk;
            if (buffered_bytes_ == sizeof(buffer_)) {
                transform(buffer_);
                buffered_bytes_ = 0;
            }
        }
    }

    void finish(uint8_t digest[32]) {
        const uint64_t bit_length = total_bytes_ * 8;
        uint8_t padding[128] = {};
        padding[0] = 0x80;
        const size_t padding_length = buffered_bytes_ < 56
            ? 56 - buffered_bytes_
            : 120 - buffered_bytes_;
        update(padding, padding_length);

        uint8_t length_bytes[8] = {};
        for (int i = 0; i < 8; ++i) {
            length_bytes[7 - i] = static_cast<uint8_t>(bit_length >> (i * 8));
        }
        update(length_bytes, sizeof(length_bytes));

        for (size_t i = 0; i < 8; ++i) {
            digest[i * 4] = static_cast<uint8_t>(state_[i] >> 24);
            digest[i * 4 + 1] = static_cast<uint8_t>(state_[i] >> 16);
            digest[i * 4 + 2] = static_cast<uint8_t>(state_[i] >> 8);
            digest[i * 4 + 3] = static_cast<uint8_t>(state_[i]);
        }
    }

private:
    void transform(const uint8_t block[64]) {
        static constexpr uint32_t kRoundConstants[64] = {
            0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u,
            0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
            0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u,
            0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
            0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu,
            0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
            0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u,
            0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
            0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u,
            0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
            0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u,
            0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
            0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u,
            0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
            0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u,
            0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u,
        };
        uint32_t words[64] = {};
        for (size_t i = 0; i < 16; ++i) {
            words[i] = (static_cast<uint32_t>(block[i * 4]) << 24) |
                (static_cast<uint32_t>(block[i * 4 + 1]) << 16) |
                (static_cast<uint32_t>(block[i * 4 + 2]) << 8) |
                static_cast<uint32_t>(block[i * 4 + 3]);
        }
        for (size_t i = 16; i < 64; ++i) {
            const uint32_t s0 = rotate_right(words[i - 15], 7) ^
                rotate_right(words[i - 15], 18) ^ (words[i - 15] >> 3);
            const uint32_t s1 = rotate_right(words[i - 2], 17) ^
                rotate_right(words[i - 2], 19) ^ (words[i - 2] >> 10);
            words[i] = words[i - 16] + s0 + words[i - 7] + s1;
        }

        uint32_t a = state_[0];
        uint32_t b = state_[1];
        uint32_t c = state_[2];
        uint32_t d = state_[3];
        uint32_t e = state_[4];
        uint32_t f = state_[5];
        uint32_t g = state_[6];
        uint32_t h = state_[7];
        for (size_t i = 0; i < 64; ++i) {
            const uint32_t s1 = rotate_right(e, 6) ^ rotate_right(e, 11) ^ rotate_right(e, 25);
            const uint32_t choice = (e & f) ^ ((~e) & g);
            const uint32_t temporary1 = h + s1 + choice + kRoundConstants[i] + words[i];
            const uint32_t s0 = rotate_right(a, 2) ^ rotate_right(a, 13) ^ rotate_right(a, 22);
            const uint32_t majority = (a & b) ^ (a & c) ^ (b & c);
            const uint32_t temporary2 = s0 + majority;
            h = g;
            g = f;
            f = e;
            e = d + temporary1;
            d = c;
            c = b;
            b = a;
            a = temporary1 + temporary2;
        }

        state_[0] += a;
        state_[1] += b;
        state_[2] += c;
        state_[3] += d;
        state_[4] += e;
        state_[5] += f;
        state_[6] += g;
        state_[7] += h;
    }

    uint32_t state_[8];
    uint64_t total_bytes_;
    size_t buffered_bytes_;
    uint8_t buffer_[64] = {};
};

static bool hash_file(const char* path, uint8_t digest[32], uint64_t* size_out) {
    if (path == nullptr || digest == nullptr) {
        return false;
    }
    const int fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) {
        return false;
    }
    struct stat file_stat = {};
    if (fstat(fd, &file_stat) != 0 || !S_ISREG(file_stat.st_mode)) {
        close(fd);
        return false;
    }

    Sha256 sha256;
    uint8_t buffer[16384];
    bool success = true;
    for (;;) {
        const ssize_t count = read(fd, buffer, sizeof(buffer));
        if (count == 0) {
            break;
        }
        if (count < 0) {
            if (errno == EINTR) {
                continue;
            }
            success = false;
            break;
        }
        sha256.update(buffer, static_cast<size_t>(count));
    }
    if (success) {
        sha256.finish(digest);
        if (size_out != nullptr) {
            *size_out = static_cast<uint64_t>(file_stat.st_size);
        }
    }
    close(fd);
    return success;
}

static void digest_to_hex(const uint8_t digest[32], char output[65]) {
    static constexpr char kHex[] = "0123456789abcdef";
    for (size_t i = 0; i < 32; ++i) {
        output[i * 2] = kHex[digest[i] >> 4];
        output[i * 2 + 1] = kHex[digest[i] & 0x0f];
    }
    output[64] = '\0';
}

static bool is_arm64_elf(const char* path) {
    const int fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) {
        return false;
    }
    uint8_t header[20] = {};
    size_t received = 0;
    while (received < sizeof(header)) {
        const ssize_t count = read(fd, header + received, sizeof(header) - received);
        if (count == 0) {
            break;
        }
        if (count < 0 && errno == EINTR) {
            continue;
        }
        if (count < 0) {
            break;
        }
        received += static_cast<size_t>(count);
    }
    close(fd);
    return received == sizeof(header) &&
        header[0] == 0x7f && header[1] == 'E' && header[2] == 'L' && header[3] == 'F' &&
        header[4] == 2 && header[5] == 1 && header[18] == 0xb7 && header[19] == 0;
}

static bool digest_equal(const uint8_t left[32], const uint8_t right[32]) {
    uint8_t difference = 0;
    for (size_t i = 0; i < 32; ++i) {
        difference |= left[i] ^ right[i];
    }
    return difference == 0;
}

static bool copy_file(const char* source, const char* destination, uid_t uid, gid_t gid) {
    const int source_fd = open(source, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (source_fd < 0) {
        return false;
    }
    const int destination_fd = open(
        destination,
        O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW,
        0700);
    if (destination_fd < 0) {
        close(source_fd);
        return false;
    }

    uint8_t buffer[16384];
    bool success = true;
    for (;;) {
        const ssize_t count = read(source_fd, buffer, sizeof(buffer));
        if (count == 0) {
            break;
        }
        if (count < 0) {
            if (errno == EINTR) {
                continue;
            }
            success = false;
            break;
        }
        size_t written = 0;
        while (written < static_cast<size_t>(count)) {
            const ssize_t result = write(destination_fd, buffer + written, static_cast<size_t>(count) - written);
            if (result < 0 && errno == EINTR) {
                continue;
            }
            if (result <= 0) {
                success = false;
                break;
            }
            written += static_cast<size_t>(result);
        }
        if (!success) {
            break;
        }
    }

    if (success && fchown(destination_fd, uid, gid) != 0) {
        success = false;
    }
    if (success && fchmod(destination_fd, 0700) != 0) {
        success = false;
    }
    if (success && fsync(destination_fd) != 0) {
        success = false;
    }
    close(destination_fd);
    close(source_fd);
    if (!success) {
        unlink(destination);
    }
    return success;
}

static bool ensure_private_files_directory(const char* path, uid_t uid, gid_t gid) {
    struct stat existing = {};
    if (lstat(path, &existing) == 0) {
        if (!S_ISDIR(existing.st_mode)) {
            return false;
        }
    } else if (errno == ENOENT) {
        if (mkdir(path, 0700) != 0 && errno != EEXIST) {
            return false;
        }
        if (lstat(path, &existing) != 0 || !S_ISDIR(existing.st_mode)) {
            return false;
        }
    } else {
        return false;
    }
    return chown(path, uid, gid) == 0 && chmod(path, 0700) == 0;
}

static bool has_process_library(const char* library_name) {
    FILE* maps = fopen("/proc/self/maps", "re");
    if (maps == nullptr) {
        return false;
    }
    char line[1024];
    bool found = false;
    while (fgets(line, sizeof(line), maps) != nullptr) {
        if (strstr(line, library_name) != nullptr) {
            found = true;
            break;
        }
    }
    fclose(maps);
    return found;
}

struct ProcessMapping {
    uintptr_t start = 0;
    uintptr_t end = 0;
    uintptr_t file_offset = 0;
    char permissions[5] = {};
    char path[512] = {};
};

static bool parse_process_mapping(const char* line, ProcessMapping* mapping) {
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

static bool find_process_mapping(uintptr_t address, const char* path_needle, ProcessMapping* result) {
    FILE* maps = fopen("/proc/self/maps", "re");
    if (maps == nullptr) {
        return false;
    }
    char line[1024];
    bool found = false;
    while (fgets(line, sizeof(line), maps) != nullptr) {
        ProcessMapping mapping = {};
        if (!parse_process_mapping(line, &mapping) || address < mapping.start || address >= mapping.end) {
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

static uintptr_t find_process_module_base(const char* path_needle) {
    FILE* maps = fopen("/proc/self/maps", "re");
    if (maps == nullptr) {
        return 0;
    }
    char line[1024];
    uintptr_t base = 0;
    while (fgets(line, sizeof(line), maps) != nullptr) {
        ProcessMapping mapping = {};
        if (!parse_process_mapping(line, &mapping)) {
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

static bool target_frame_rate_icall_ready(uintptr_t* cache_address_out, uintptr_t* target_out) {
    const uintptr_t libil2cpp_base = find_process_module_base("/libil2cpp.so");
    if (libil2cpp_base == 0) {
        return false;
    }
    const uintptr_t cache_address = libil2cpp_base + 0x5612250;
    ProcessMapping cache_mapping = {};
    if (!find_process_mapping(cache_address, nullptr, &cache_mapping) ||
        cache_mapping.permissions[0] != 'r') {
        return false;
    }
    if (cache_mapping.permissions[1] != 'w') {
        return false;
    }
    const uintptr_t target = *reinterpret_cast<volatile uintptr_t*>(cache_address);
    if (target == 0) {
        return false;
    }
    ProcessMapping target_mapping = {};
    if (!find_process_mapping(target, "/libunity.so", &target_mapping)) {
        return false;
    }
    if (cache_address_out != nullptr) {
        *cache_address_out = cache_address;
    }
    if (target_out != nullptr) {
        *target_out = target;
    }
    return true;
}

struct VersionInfo {
    char name[64] = {};
    jint code = 0;
};

enum class VersionStatus {
    kNotReady,
    kSupported,
    kUnsupported,
    kError,
};

static jobject current_application(JNIEnv* env) {
    if (env == nullptr) {
        return nullptr;
    }
    jclass activity_thread = env->FindClass("android/app/ActivityThread");
    if (activity_thread == nullptr || env->ExceptionCheck()) {
        clear_pending_exception(env);
        if (activity_thread != nullptr) {
            env->DeleteLocalRef(activity_thread);
        }
        return nullptr;
    }
    const jmethodID current_application_method = env->GetStaticMethodID(
        activity_thread,
        "currentApplication",
        "()Landroid/app/Application;");
    if (current_application_method == nullptr || env->ExceptionCheck()) {
        clear_pending_exception(env);
        env->DeleteLocalRef(activity_thread);
        return nullptr;
    }
    jobject application = env->CallStaticObjectMethod(activity_thread, current_application_method);
    if (env->ExceptionCheck()) {
        clear_pending_exception(env);
        application = nullptr;
    }
    env->DeleteLocalRef(activity_thread);
    return application;
}

static VersionStatus read_target_version(JNIEnv* env, VersionInfo* result) {
    if (env == nullptr || result == nullptr) {
        return VersionStatus::kError;
    }

    jobject application = current_application(env);
    if (application == nullptr) {
        return VersionStatus::kNotReady;
    }

    jclass context = env->FindClass("android/content/Context");
    if (context == nullptr || env->ExceptionCheck()) {
        clear_pending_exception(env);
        if (context != nullptr) {
            env->DeleteLocalRef(context);
        }
        env->DeleteLocalRef(application);
        return VersionStatus::kNotReady;
    }
    const jmethodID get_package_name = env->GetMethodID(
        context,
        "getPackageName",
        "()Ljava/lang/String;");
    const jmethodID get_package_manager = env->GetMethodID(
        context,
        "getPackageManager",
        "()Landroid/content/pm/PackageManager;");
    if (get_package_name == nullptr || get_package_manager == nullptr || env->ExceptionCheck()) {
        clear_pending_exception(env);
        env->DeleteLocalRef(context);
        env->DeleteLocalRef(application);
        return VersionStatus::kError;
    }
    jstring package_name = static_cast<jstring>(env->CallObjectMethod(application, get_package_name));
    jobject package_manager = env->CallObjectMethod(application, get_package_manager);
    if (env->ExceptionCheck() || package_name == nullptr || package_manager == nullptr) {
        clear_pending_exception(env);
        if (package_name != nullptr) {
            env->DeleteLocalRef(package_name);
        }
        if (package_manager != nullptr) {
            env->DeleteLocalRef(package_manager);
        }
        env->DeleteLocalRef(context);
        env->DeleteLocalRef(application);
        return VersionStatus::kNotReady;
    }

    const char* package_name_text = env->GetStringUTFChars(package_name, nullptr);
    const bool package_matches = package_name_text != nullptr && strcmp(package_name_text, kTargetPackage) == 0;
    if (package_name_text != nullptr) {
        env->ReleaseStringUTFChars(package_name, package_name_text);
    }
    clear_pending_exception(env);
    if (!package_matches) {
        env->DeleteLocalRef(package_name);
        env->DeleteLocalRef(package_manager);
        env->DeleteLocalRef(context);
        env->DeleteLocalRef(application);
        return VersionStatus::kUnsupported;
    }

    jclass package_manager_class = env->FindClass("android/content/pm/PackageManager");
    const jmethodID get_package_info = package_manager_class != nullptr && !env->ExceptionCheck()
        ? env->GetMethodID(package_manager_class, "getPackageInfo", "(Ljava/lang/String;I)Landroid/content/pm/PackageInfo;")
        : nullptr;
    if (package_manager_class == nullptr || get_package_info == nullptr || env->ExceptionCheck()) {
        clear_pending_exception(env);
        if (package_manager_class != nullptr) {
            env->DeleteLocalRef(package_manager_class);
        }
        env->DeleteLocalRef(package_name);
        env->DeleteLocalRef(package_manager);
        env->DeleteLocalRef(context);
        env->DeleteLocalRef(application);
        return VersionStatus::kError;
    }
    jobject package_info = env->CallObjectMethod(package_manager, get_package_info, package_name, 0);
    if (env->ExceptionCheck() || package_info == nullptr) {
        clear_pending_exception(env);
        env->DeleteLocalRef(package_manager_class);
        env->DeleteLocalRef(package_name);
        env->DeleteLocalRef(package_manager);
        env->DeleteLocalRef(context);
        env->DeleteLocalRef(application);
        return VersionStatus::kNotReady;
    }

    jclass package_info_class = env->FindClass("android/content/pm/PackageInfo");
    const jfieldID version_name_field = package_info_class != nullptr && !env->ExceptionCheck()
        ? env->GetFieldID(package_info_class, "versionName", "Ljava/lang/String;")
        : nullptr;
    const jfieldID version_code_field = package_info_class != nullptr && !env->ExceptionCheck()
        ? env->GetFieldID(package_info_class, "versionCode", "I")
        : nullptr;
    if (package_info_class == nullptr || version_name_field == nullptr || version_code_field == nullptr || env->ExceptionCheck()) {
        clear_pending_exception(env);
        if (package_info_class != nullptr) {
            env->DeleteLocalRef(package_info_class);
        }
        env->DeleteLocalRef(package_info);
        env->DeleteLocalRef(package_manager_class);
        env->DeleteLocalRef(package_name);
        env->DeleteLocalRef(package_manager);
        env->DeleteLocalRef(context);
        env->DeleteLocalRef(application);
        return VersionStatus::kError;
    }

    jstring version_name = static_cast<jstring>(env->GetObjectField(package_info, version_name_field));
    const jint version_code = env->GetIntField(package_info, version_code_field);
    const char* version_name_text = version_name != nullptr
        ? env->GetStringUTFChars(version_name, nullptr)
        : nullptr;
    if (version_name_text == nullptr || env->ExceptionCheck()) {
        clear_pending_exception(env);
        if (version_name != nullptr) {
            env->DeleteLocalRef(version_name);
        }
        env->DeleteLocalRef(package_info_class);
        env->DeleteLocalRef(package_info);
        env->DeleteLocalRef(package_manager_class);
        env->DeleteLocalRef(package_name);
        env->DeleteLocalRef(package_manager);
        env->DeleteLocalRef(context);
        env->DeleteLocalRef(application);
        return VersionStatus::kNotReady;
    }
    strncpy(result->name, version_name_text, sizeof(result->name) - 1);
    result->name[sizeof(result->name) - 1] = '\0';
    result->code = version_code;
    env->ReleaseStringUTFChars(version_name, version_name_text);
    env->DeleteLocalRef(version_name);
    env->DeleteLocalRef(package_info_class);
    env->DeleteLocalRef(package_info);
    env->DeleteLocalRef(package_manager_class);
    env->DeleteLocalRef(package_name);
    env->DeleteLocalRef(package_manager);
    env->DeleteLocalRef(context);
    env->DeleteLocalRef(application);
    clear_pending_exception(env);

    return strcmp(result->name, kRequiredVersionName) == 0 && result->code == kRequiredVersionCode
        ? VersionStatus::kSupported
        : VersionStatus::kUnsupported;
}

static jclass resolve_runtime_caller_class(JNIEnv* env, jobject application) {
    if (env == nullptr || application == nullptr) {
        return nullptr;
    }
    jclass application_class = env->GetObjectClass(application);
    jclass class_class = env->FindClass("java/lang/Class");
    if (application_class == nullptr || class_class == nullptr || env->ExceptionCheck()) {
        clear_pending_exception(env);
        if (application_class != nullptr) {
            env->DeleteLocalRef(application_class);
        }
        if (class_class != nullptr) {
            env->DeleteLocalRef(class_class);
        }
        return nullptr;
    }
    const jmethodID get_class_loader = env->GetMethodID(
        class_class,
        "getClassLoader",
        "()Ljava/lang/ClassLoader;");
    if (get_class_loader == nullptr || env->ExceptionCheck()) {
        clear_pending_exception(env);
        env->DeleteLocalRef(class_class);
        return application_class;
    }
    jobject application_loader = env->CallObjectMethod(application_class, get_class_loader);
    if (env->ExceptionCheck() || application_loader == nullptr) {
        clear_pending_exception(env);
        if (application_loader != nullptr) {
            env->DeleteLocalRef(application_loader);
        }
        env->DeleteLocalRef(class_class);
        return application_class;
    }
    jclass loader_class = env->FindClass("java/lang/ClassLoader");
    const jmethodID load_class = loader_class != nullptr && !env->ExceptionCheck()
        ? env->GetMethodID(loader_class, "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;")
        : nullptr;
    if (loader_class == nullptr || load_class == nullptr || env->ExceptionCheck()) {
        clear_pending_exception(env);
        if (loader_class != nullptr) {
            env->DeleteLocalRef(loader_class);
        }
        env->DeleteLocalRef(application_loader);
        env->DeleteLocalRef(class_class);
        return application_class;
    }
    jstring activity_name = env->NewStringUTF("com.unity3d.player.UnityPlayerActivity");
    jclass unity_activity = activity_name != nullptr && !env->ExceptionCheck()
        ? static_cast<jclass>(env->CallObjectMethod(application_loader, load_class, activity_name))
        : nullptr;
    const bool unity_activity_valid = unity_activity != nullptr && !env->ExceptionCheck();
    clear_pending_exception(env);
    if (activity_name != nullptr) {
        env->DeleteLocalRef(activity_name);
    }
    env->DeleteLocalRef(loader_class);
    env->DeleteLocalRef(application_loader);
    env->DeleteLocalRef(class_class);
    if (unity_activity_valid) {
        env->DeleteLocalRef(application_class);
        return unity_activity;
    }
    if (unity_activity != nullptr) {
        env->DeleteLocalRef(unity_activity);
    }
    return application_class;
}

static bool invoke_runtime_load0(JNIEnv* env, const char* payload_path) {
    if (env == nullptr || payload_path == nullptr) {
        return false;
    }
    jclass runtime_class = env->FindClass("java/lang/Runtime");
    jobject application = current_application(env);
    jclass caller_class = resolve_runtime_caller_class(env, application);
    if (runtime_class == nullptr || application == nullptr || caller_class == nullptr || env->ExceptionCheck()) {
        clear_pending_exception(env);
        if (runtime_class != nullptr) {
            env->DeleteLocalRef(runtime_class);
        }
        if (caller_class != nullptr) {
            env->DeleteLocalRef(caller_class);
        }
        if (application != nullptr) {
            env->DeleteLocalRef(application);
        }
        return false;
    }
    const jmethodID get_runtime = env->GetStaticMethodID(
        runtime_class,
        "getRuntime",
        "()Ljava/lang/Runtime;");
    const jmethodID load0 = env->GetMethodID(
        runtime_class,
        "load0",
        "(Ljava/lang/Class;Ljava/lang/String;)V");
    if (get_runtime == nullptr || load0 == nullptr || env->ExceptionCheck()) {
        clear_pending_exception(env);
        env->DeleteLocalRef(runtime_class);
        env->DeleteLocalRef(caller_class);
        env->DeleteLocalRef(application);
        return false;
    }
    jobject runtime = env->CallStaticObjectMethod(runtime_class, get_runtime);
    if (runtime == nullptr || env->ExceptionCheck()) {
        clear_pending_exception(env);
        env->DeleteLocalRef(runtime_class);
        env->DeleteLocalRef(caller_class);
        env->DeleteLocalRef(application);
        if (runtime != nullptr) {
            env->DeleteLocalRef(runtime);
        }
        return false;
    }
    jstring path = env->NewStringUTF(payload_path);
    if (path == nullptr || env->ExceptionCheck()) {
        clear_pending_exception(env);
        env->DeleteLocalRef(runtime);
        env->DeleteLocalRef(runtime_class);
        env->DeleteLocalRef(caller_class);
        env->DeleteLocalRef(application);
        if (path != nullptr) {
            env->DeleteLocalRef(path);
        }
        return false;
    }

    log_message(ANDROID_LOG_INFO, "PCFPS-ZB: RUNTIME_LOAD0_BEGIN caller=app-class");
    env->CallVoidMethod(runtime, load0, caller_class, path);
    const bool success = !env->ExceptionCheck();
    if (!success) {
        log_message(ANDROID_LOG_ERROR, "PCFPS-ZB: RUNTIME_LOAD0_EXCEPTION fail_open=yes");
        env->ExceptionDescribe();
        clear_pending_exception(env);
    } else {
        log_message(ANDROID_LOG_INFO, "PCFPS-ZB: RUNTIME_LOAD0_RETURNED");
    }

    env->DeleteLocalRef(path);
    env->DeleteLocalRef(runtime);
    env->DeleteLocalRef(runtime_class);
    env->DeleteLocalRef(caller_class);
    env->DeleteLocalRef(application);
    clear_pending_exception(env);
    return success;
}

class PcfpsZygiskBootstrap final : public zygisk::ModuleBase {
public:
    void onLoad(zygisk::Api* api, JNIEnv* env) override {
        api_ = api;
        env_ = env;
        if (env_ != nullptr) {
            env_->GetJavaVM(&vm_);
        }
    }

    void preAppSpecialize(zygisk::AppSpecializeArgs* args) override {
        target_process_ = false;
        staged_ = false;
        if (api_ == nullptr || env_ == nullptr || args == nullptr || args->nice_name == nullptr) {
            return;
        }

        const char* app = env_->GetStringUTFChars(args->nice_name, nullptr);
        if (app == nullptr) {
            clear_pending_exception(env_);
            api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            return;
        }
        target_process_ = strcmp(app, kTargetPackage) == 0;
        env_->ReleaseStringUTFChars(args->nice_name, app);
        clear_pending_exception(env_);

        if (!target_process_) {
            api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            return;
        }

        log_message(ANDROID_LOG_INFO, "PCFPS-ZB: TARGET_MATCHED abi=x86_64");
        staged_ = stage_payload(args);
        if (!staged_) {
            log_message(ANDROID_LOG_ERROR, "PCFPS-ZB: STAGE_FAILED fail_open=yes");
        }
    }

    void postAppSpecialize(const zygisk::AppSpecializeArgs* args) override {
        (void)args;
        if (!target_process_) {
            return;
        }
        if (!staged_) {
            log_message(ANDROID_LOG_ERROR, "PCFPS-ZB: POST_SKIP stage_failed fail_open=yes");
            return;
        }
        if (vm_ == nullptr) {
            log_message(ANDROID_LOG_ERROR, "PCFPS-ZB: POST_SKIP java_vm_missing fail_open=yes");
            return;
        }
        pthread_t worker = {};
        const int result = pthread_create(&worker, nullptr, &PcfpsZygiskBootstrap::worker_entry, this);
        if (result != 0) {
            log_message(ANDROID_LOG_ERROR, "PCFPS-ZB: WORKER_CREATE_FAILED errno=%d fail_open=yes", result);
            return;
        }
        pthread_detach(worker);
        log_message(ANDROID_LOG_INFO, "PCFPS-ZB: POST_WORKER_STARTED");
    }

private:
    bool stage_payload(const zygisk::AppSpecializeArgs* args) {
        if (args == nullptr || args->app_data_dir == nullptr || args->uid <= 0 || args->gid <= 0) {
            log_message(ANDROID_LOG_ERROR, "PCFPS-ZB: STAGE_INPUT_INVALID");
            return false;
        }
        ScopedFd module_dir(api_->getModuleDir());
        if (module_dir.get() < 0) {
            log_message(ANDROID_LOG_ERROR, "PCFPS-ZB: MODULE_DIR_FAILED");
            return false;
        }

        char source_path[PATH_MAX] = {};
        const int source_length = snprintf(
            source_path,
            sizeof(source_path),
            "/proc/self/fd/%d/%s",
            module_dir.get(),
            kPayloadRelativePath);
        if (source_length <= 0 || static_cast<size_t>(source_length) >= sizeof(source_path)) {
            log_message(ANDROID_LOG_ERROR, "PCFPS-ZB: SOURCE_PATH_TOO_LONG");
            return false;
        }

        uint8_t source_digest[32] = {};
        uint64_t source_size = 0;
        const bool source_hashed = hash_file(source_path, source_digest, &source_size);
        const bool source_is_arm64 = source_hashed && is_arm64_elf(source_path);
        char source_hex[65] = {};
        if (source_hashed) {
            digest_to_hex(source_digest, source_hex);
        }
        if (!source_hashed || !source_is_arm64 || source_size == 0) {
            log_message(
                ANDROID_LOG_ERROR,
                "PCFPS-ZB: SOURCE_INVALID hashed=%s arm64_elf=%s size=%llu",
                source_hashed ? "yes" : "no",
                source_is_arm64 ? "yes" : "no",
                static_cast<unsigned long long>(source_size));
            return false;
        }
        log_message(
            ANDROID_LOG_INFO,
            "PCFPS-ZB: SOURCE_OK size=%llu sha256=%s",
            static_cast<unsigned long long>(source_size),
            source_hex);

        const char* data_dir_text = env_->GetStringUTFChars(args->app_data_dir, nullptr);
        if (data_dir_text == nullptr) {
            clear_pending_exception(env_);
            return false;
        }
        char data_dir[PATH_MAX] = {};
        strncpy(data_dir, data_dir_text, sizeof(data_dir) - 1);
        data_dir[sizeof(data_dir) - 1] = '\0';
        env_->ReleaseStringUTFChars(args->app_data_dir, data_dir_text);
        clear_pending_exception(env_);

        const uid_t uid = static_cast<uid_t>(args->uid);
        const gid_t gid = static_cast<gid_t>(args->gid);
        char files_dir[PATH_MAX] = {};
        char destination[PATH_MAX] = {};
        char temporary[PATH_MAX] = {};
        const int files_length = snprintf(files_dir, sizeof(files_dir), "%s/files", data_dir);
        const int destination_length = snprintf(destination, sizeof(destination), "%s/%s", files_dir, kPayloadFileName);
        const int temporary_length = snprintf(temporary, sizeof(temporary), "%s/.%s.tmp.%d", files_dir, kPayloadFileName, getpid());
        if (files_length <= 0 || destination_length <= 0 || temporary_length <= 0 ||
            static_cast<size_t>(files_length) >= sizeof(files_dir) ||
            static_cast<size_t>(destination_length) >= sizeof(destination) ||
            static_cast<size_t>(temporary_length) >= sizeof(temporary)) {
            log_message(ANDROID_LOG_ERROR, "PCFPS-ZB: DESTINATION_PATH_TOO_LONG");
            return false;
        }
        if (!ensure_private_files_directory(files_dir, uid, gid)) {
            log_message(ANDROID_LOG_ERROR, "PCFPS-ZB: FILES_DIR_FAILED path=%s", files_dir);
            return false;
        }

        uint8_t destination_digest[32] = {};
        uint64_t destination_size = 0;
        const bool destination_matches =
            hash_file(destination, destination_digest, &destination_size) &&
            destination_size == source_size &&
            digest_equal(source_digest, destination_digest);
        if (destination_matches) {
            if (chown(destination, uid, gid) != 0 || chmod(destination, 0700) != 0) {
                log_message(ANDROID_LOG_ERROR, "PCFPS-ZB: DESTINATION_ATTRIBUTES_FAILED path=%s", destination);
                return false;
            }
            log_message(ANDROID_LOG_INFO, "PCFPS-ZB: STAGE_REUSE sha256=%s", source_hex);
        } else {
            unlink(temporary);
            if (!copy_file(source_path, temporary, uid, gid)) {
                log_message(ANDROID_LOG_ERROR, "PCFPS-ZB: COPY_FAILED path=%s", temporary);
                return false;
            }
            uint8_t temporary_digest[32] = {};
            uint64_t temporary_size = 0;
            if (!hash_file(temporary, temporary_digest, &temporary_size) ||
                temporary_size != source_size || !digest_equal(source_digest, temporary_digest)) {
                unlink(temporary);
                log_message(ANDROID_LOG_ERROR, "PCFPS-ZB: TEMP_HASH_MISMATCH");
                return false;
            }
            if (rename(temporary, destination) != 0 || chown(destination, uid, gid) != 0 || chmod(destination, 0700) != 0) {
                unlink(temporary);
                log_message(ANDROID_LOG_ERROR, "PCFPS-ZB: RENAME_FAILED path=%s", destination);
                return false;
            }
            uint8_t final_digest[32] = {};
            uint64_t final_size = 0;
            if (!hash_file(destination, final_digest, &final_size) ||
                final_size != source_size || !digest_equal(source_digest, final_digest)) {
                log_message(ANDROID_LOG_ERROR, "PCFPS-ZB: FINAL_HASH_MISMATCH path=%s", destination);
                return false;
            }
            log_message(ANDROID_LOG_INFO, "PCFPS-ZB: STAGE_REPLACED sha256=%s", source_hex);
        }

        strncpy(staged_path_, destination, sizeof(staged_path_) - 1);
        staged_path_[sizeof(staged_path_) - 1] = '\0';
        return true;
    }

    static void* worker_entry(void* argument) {
        static_cast<PcfpsZygiskBootstrap*>(argument)->run_worker();
        return nullptr;
    }

    void run_worker() {
        JNIEnv* env = nullptr;
        JavaVMAttachArgs attach_args = {
            JNI_VERSION_1_6,
            const_cast<char*>("pcfps-zygisk-bootstrap"),
            nullptr,
        };
        if (vm_->AttachCurrentThread(&env, &attach_args) != JNI_OK || env == nullptr) {
            log_message(ANDROID_LOG_ERROR, "PCFPS-ZB: WORKER_ATTACH_FAILED fail_open=yes");
            return;
        }

        VersionInfo version = {};
        VersionStatus version_status = VersionStatus::kNotReady;
        for (int attempt = 0; attempt < kPollAttempts; ++attempt) {
            version_status = read_target_version(env, &version);
            if (version_status == VersionStatus::kSupported ||
                version_status == VersionStatus::kUnsupported ||
                version_status == VersionStatus::kError) {
                break;
            }
            usleep(kPollIntervalUs);
        }
        if (version_status == VersionStatus::kUnsupported) {
            log_message(
                ANDROID_LOG_ERROR,
                "PCFPS-ZB: UNSUPPORTED_VERSION name=%s code=%d fail_open=yes",
                version.name,
                version.code);
            vm_->DetachCurrentThread();
            return;
        }
        if (version_status == VersionStatus::kError) {
            log_message(ANDROID_LOG_ERROR, "PCFPS-ZB: VERSION_GUARD_ERROR fail_open=yes");
            vm_->DetachCurrentThread();
            return;
        }
        if (version_status != VersionStatus::kSupported) {
            log_message(ANDROID_LOG_ERROR, "PCFPS-ZB: VERSION_GUARD_TIMEOUT fail_open=yes");
            vm_->DetachCurrentThread();
            return;
        }
        log_message(ANDROID_LOG_INFO, "PCFPS-ZB: VERSION_GUARD_OK");

        bool libraries_ready = false;
        for (int attempt = 0; attempt < kPollAttempts; ++attempt) {
            if (has_process_library("libil2cpp.so") && has_process_library("libunity.so")) {
                libraries_ready = true;
                break;
            }
            usleep(kPollIntervalUs);
        }
        if (!libraries_ready) {
            log_message(ANDROID_LOG_ERROR, "PCFPS-ZB: UNITY_LIBRARIES_TIMEOUT fail_open=yes");
            vm_->DetachCurrentThread();
            return;
        }
        log_message(ANDROID_LOG_INFO, "PCFPS-ZB: UNITY_LIBRARIES_MAPPED");

        bool icall_ready = false;
        uintptr_t cache_address = 0;
        uintptr_t target_address = 0;
        for (int attempt = 0; attempt < kPollAttempts; ++attempt) {
            if (target_frame_rate_icall_ready(&cache_address, &target_address)) {
                icall_ready = true;
                break;
            }
            usleep(kPollIntervalUs);
        }
        if (!icall_ready) {
            log_message(ANDROID_LOG_ERROR, "PCFPS-ZB: TARGET_ICALL_TIMEOUT fail_open=yes");
            vm_->DetachCurrentThread();
            return;
        }
        log_message(ANDROID_LOG_INFO, "PCFPS-ZB: TARGET_ICALL_READY");
        invoke_runtime_load0(env, staged_path_);
        vm_->DetachCurrentThread();
    }

    zygisk::Api* api_ = nullptr;
    JNIEnv* env_ = nullptr;
    JavaVM* vm_ = nullptr;
    bool target_process_ = false;
    bool staged_ = false;
    char staged_path_[PATH_MAX] = {};
};

}  // namespace

REGISTER_ZYGISK_MODULE(PcfpsZygiskBootstrap)
