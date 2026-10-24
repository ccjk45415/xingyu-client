#include "patch_bootstrap.h"
#include <windows.h>
#include <shlobj.h>
#include <cstdio>
#include <cstdint>
#include <fstream>
#include <iterator>

namespace {
// Equivalent to updater_engine.h in the pinned engine (not a Dart FFI ABI).
struct AppParameters {
  const char* release_version;
  const char* const* original_libapp_paths;
  int original_libapp_paths_size;
  const char* app_storage_dir;
  const char* code_cache_dir;
};
struct FileCallbacks {
  void* (*open)();
  uintptr_t (*read)(void*, uint8_t*, uintptr_t);
  int64_t (*seek)(void*, int64_t, int32_t);
  void (*close)(void*);
};
std::filesystem::path original;
bool ready = false;
void* Open() { FILE* file = nullptr; _wfopen_s(&file, original.c_str(), L"rb"); return file; }
uintptr_t Read(void* file, uint8_t* out, uintptr_t size) { return fread(out, 1, size, static_cast<FILE*>(file)); }
int64_t Seek(void* file, int64_t offset, int32_t whence) {
  return _fseeki64(static_cast<FILE*>(file), offset, whence) ? -1 : _ftelli64(static_cast<FILE*>(file));
}
void Close(void* file) { fclose(static_cast<FILE*>(file)); }
}
bool PatchBootstrapReady() { return ready; }
std::wstring PreparePatch(const std::filesystem::path& root) {
  original = root / L"data" / L"app.so";
  const auto fallback = original.wstring();
  // Resolve only the DLL shipped beside our executable, never the search PATH.
  HMODULE engine = LoadLibraryExW((root / L"flutter_windows.dll").c_str(), nullptr, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
  if (!engine) return fallback;
  const auto init = reinterpret_cast<bool (*)(const AppParameters*, FileCallbacks, const char*)>(GetProcAddress(engine, "shorebird_init"));
  const auto validate = reinterpret_cast<void (*)()>(GetProcAddress(engine, "shorebird_validate_next_boot_patch"));
  const auto next = reinterpret_cast<char* (*)()>(GetProcAddress(engine, "shorebird_next_boot_patch_path"));
  const auto free_string = reinterpret_cast<void (*)(const char*)>(GetProcAddress(engine, "shorebird_free_string"));
  if (!init || !validate || !next || !free_string) return fallback;
  try {
    std::ifstream stream(root / L"data" / L"flutter_assets" / L"shorebird.yaml", std::ios::binary);
    const std::string yaml((std::istreambuf_iterator<char>(stream)), std::istreambuf_iterator<char>());
    // Read the app id from the bundled configuration, never a remote input.
    const std::string prefix = "app_id:";
    auto start = yaml.find(prefix);
    if (start == std::string::npos) return fallback;
    start = yaml.find_first_not_of(" \t", start + prefix.size());
    const auto app_id = yaml.substr(start, yaml.find_first_of("\r\n #", start) - start);
    if (app_id.empty() || app_id.find_first_not_of("0123456789abcdef-") != std::string::npos) return fallback;
    PWSTR folder = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &folder))) return fallback;
    std::filesystem::path cache = std::filesystem::path(folder) / L"shorebird_updater" / app_id;
    CoTaskMemFree(folder);
    std::filesystem::create_directories(cache);
    const auto aot = original.u8string(), storage = cache.u8string();
    const char* paths[] = {aot.c_str()};
    AppParameters params{FLUTTER_VERSION, paths, 1, storage.c_str(), storage.c_str()};
    ready = init(&params, {Open, Read, Seek, Close}, yaml.c_str());
    if (!ready) return fallback;
    validate();
    char* selected = next();
    std::filesystem::path patch;
    if (selected) { patch = std::filesystem::u8path(selected); free_string(selected); }
    return patch.empty() ? fallback : patch.wstring();
  } catch (...) { return fallback; }
}
