#include "secure_storage.h"
#include <windows.h>
#include <shlobj.h>
#include <wincrypt.h>
#include <flutter/standard_method_codec.h>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>
#include <stdexcept>

namespace {
std::filesystem::path StorageFile(const std::string& key) {
  if (key.empty() || key.size() > 120 || key.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-") != std::string::npos || key.find("..") != std::string::npos) throw std::runtime_error("Invalid storage key");
  PWSTR path = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &path))) throw std::runtime_error("Application directory unavailable");
  const std::filesystem::path root = std::filesystem::path(path) / L"XingyuDesktop" / L"Secure";
  CoTaskMemFree(path); std::filesystem::create_directories(root);
  return root / (key + ".bin");
}
std::vector<BYTE> Protect(const std::vector<BYTE>& input, bool encrypt) {
  DATA_BLOB data{static_cast<DWORD>(input.size()), const_cast<BYTE*>(input.data())}, output{};
  const char entropy_text[] = "moe.cangku.xingyu.desktop.v1";
  DATA_BLOB entropy{sizeof(entropy_text), reinterpret_cast<BYTE*>(const_cast<char*>(entropy_text))};
  const BOOL ok = encrypt ? CryptProtectData(&data, L"Xingyu session", &entropy, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output) : CryptUnprotectData(&data, nullptr, &entropy, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output);
  if (!ok) throw std::runtime_error("Windows user-bound encryption unavailable");
  std::vector<BYTE> result(output.pbData, output.pbData + output.cbData);
  SecureZeroMemory(output.pbData, output.cbData); LocalFree(output.pbData); return result;
}
std::string Argument(const flutter::EncodableMap& args, const char* key) {
  const auto found = args.find(flutter::EncodableValue(key));
  if (found == args.end()) return "";
  const auto* value = std::get_if<std::string>(&found->second);
  if (value == nullptr) throw std::runtime_error("Invalid storage argument");
  return *value;
}
}
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> RegisterSecureStorage(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(messenger, "moe.cangku.xingyu/secure_storage", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    try {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (args == nullptr) throw std::runtime_error("Missing storage arguments");
      const auto file = StorageFile(Argument(*args, "key"));
      if (call.method_name() == "read") {
        if (!std::filesystem::exists(file)) { result->Success(); return; }
        const auto size = std::filesystem::file_size(file);
        if (size == 0 || size > 131072) throw std::runtime_error("Invalid encrypted session file");
        std::ifstream stream(file, std::ios::binary); std::vector<BYTE> bytes(static_cast<size_t>(size));
        if (!stream.read(reinterpret_cast<char*>(bytes.data()), static_cast<std::streamsize>(size))) throw std::runtime_error("Cannot read encrypted session");
        auto plain = Protect(bytes, false); result->Success(flutter::EncodableValue(std::string(plain.begin(), plain.end()))); SecureZeroMemory(plain.data(), plain.size()); return;
      }
      if (call.method_name() == "write") {
        auto value = Argument(*args, "value"); if (value.size() > 65536) throw std::runtime_error("Session exceeds storage limit");
        std::vector<BYTE> plain(value.begin(), value.end()); const auto cipher = Protect(plain, true); SecureZeroMemory(plain.data(), plain.size()); SecureZeroMemory(value.data(), value.size());
        auto temp = file; temp += L"." + std::to_wstring(GetCurrentProcessId()) + L".tmp";
        { std::ofstream stream(temp, std::ios::binary | std::ios::trunc); if (!stream.write(reinterpret_cast<const char*>(cipher.data()), static_cast<std::streamsize>(cipher.size()))) throw std::runtime_error("Cannot save encrypted session"); stream.flush(); }
        if (!MoveFileExW(temp.c_str(), file.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) { std::filesystem::remove(temp); throw std::runtime_error("Cannot commit encrypted session"); }
        result->Success(); return;
      }
      if (call.method_name() == "delete") { std::filesystem::remove(file); result->Success(); return; }
      result->NotImplemented();
    } catch (const std::exception& e) { result->Error("secure_storage", e.what()); }
  });
  return channel;
}
