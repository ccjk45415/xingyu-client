#pragma once
#include <filesystem>
#include <string>

// Pinned to the engine ABI shipped by Shorebird Flutter 3.47.7.
// Wide Win32 paths are converted to UTF-8 before entering the Rust updater.
std::wstring PreparePatch(const std::filesystem::path& executable_directory);
bool PatchBootstrapReady();
