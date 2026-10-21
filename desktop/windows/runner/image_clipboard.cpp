#include "image_clipboard.h"
#include <windows.h>
#include <objidl.h>
#include <gdiplus.h>
#include <shellapi.h>
#include <flutter/standard_method_codec.h>
#include <stdexcept>
#include <vector>
#include <filesystem>
#include <fstream>

namespace {
constexpr size_t kLimit = 1024 * 1024;
struct ClipboardGuard {
  ClipboardGuard() { if (!OpenClipboard(nullptr)) throw std::runtime_error("Clipboard is busy"); }
  ~ClipboardGuard() { CloseClipboard(); }
};
std::vector<uint8_t> ReadPng() {
  ClipboardGuard guard;
  const auto png_format = RegisterClipboardFormatW(L"PNG");
  if (IsClipboardFormatAvailable(png_format)) {
    const auto handle = GetClipboardData(png_format);
    const auto size = GlobalSize(handle);
    if (size > kLimit) throw std::runtime_error("Image exceeds 1 MB");
    if (size == 0) throw std::runtime_error("Invalid clipboard image");
    const auto* data = static_cast<const uint8_t*>(GlobalLock(handle));
    if (!data) throw std::runtime_error("Cannot read clipboard image");
    std::vector<uint8_t> bytes(data, data + size);
    GlobalUnlock(handle);
    return bytes;
  }
  // Windows synthesizes CF_BITMAP from CF_DIB / CF_DIBV5 when necessary.
  if (!IsClipboardFormatAvailable(CF_BITMAP)) {
    if (!IsClipboardFormatAvailable(CF_HDROP)) return {};
    const auto files = static_cast<HDROP>(GetClipboardData(CF_HDROP));
    if (!files || DragQueryFileW(files, 0xffffffff, nullptr, 0) != 1)
      throw std::runtime_error("Paste one image file at a time");
    const UINT length = DragQueryFileW(files, 0, nullptr, 0);
    if (length == 0 || length > 32767) throw std::runtime_error("Invalid image file path");
    std::vector<wchar_t> path(static_cast<size_t>(length) + 1);
    DragQueryFileW(files, 0, path.data(), length + 1);
    const std::filesystem::path file(path.data());
    if (!std::filesystem::is_regular_file(file))
      throw std::runtime_error("Copied image is not a regular file");
    std::ifstream input(file, std::ios::binary);
    const auto size = static_cast<size_t>(std::filesystem::file_size(file));
    if (size > kLimit) throw std::runtime_error("Image exceeds 1 MB");
    std::vector<uint8_t> bytes(size);
    if (size == 0 || !input.read(reinterpret_cast<char*>(bytes.data()), static_cast<std::streamsize>(size)))
      throw std::runtime_error("Cannot read copied image file");
    return bytes; // Dart validates actual image format and decoded dimensions.
  }
  const auto handle = static_cast<HBITMAP>(GetClipboardData(CF_BITMAP));
  BITMAP info{};
  if (!handle || !GetObjectW(handle, sizeof(info), &info) || info.bmWidth <= 0 ||
      info.bmHeight <= 0 || static_cast<int64_t>(info.bmWidth) * info.bmHeight > 40000000) {
    throw std::runtime_error("Invalid clipboard image dimensions");
  }
  ULONG_PTR token = 0;
  Gdiplus::GdiplusStartupInput startup;
  if (Gdiplus::GdiplusStartup(&token, &startup, nullptr) != Gdiplus::Ok)
    throw std::runtime_error("Image encoder unavailable");
  std::vector<uint8_t> bytes;
  bool failed = false;
  {
    Gdiplus::Bitmap bitmap(handle, nullptr);
    IStream* stream = nullptr;
    // Windows' built-in PNG encoder; no temporary files or clipboard mutation.
    const CLSID png = {0x557cf406, 0x1a04, 0x11d3, {0x9a, 0x73, 0x00, 0x00, 0xf8, 0x1e, 0xf3, 0x2e}};
    if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream))) {
      failed = true;
    } else {
      if (bitmap.Save(stream, &png, nullptr) != Gdiplus::Ok) {
        failed = true;
      } else {
        STATSTG stat{};
        if (FAILED(stream->Stat(&stat, STATFLAG_NONAME)) || stat.cbSize.QuadPart > kLimit ||
            stat.cbSize.QuadPart == 0) {
          failed = true;
        } else {
          bytes.resize(static_cast<size_t>(stat.cbSize.QuadPart));
          LARGE_INTEGER zero{};
          stream->Seek(zero, STREAM_SEEK_SET, nullptr);
          ULONG read = 0;
          if (FAILED(stream->Read(bytes.data(), static_cast<ULONG>(bytes.size()), &read)) ||
              read != bytes.size()) failed = true;
        }
      }
      stream->Release();
    }
  }
  Gdiplus::GdiplusShutdown(token);
  if (failed) throw std::runtime_error("Cannot encode image or image exceeds 1 MB");
  return bytes;
}
}

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterImageClipboard(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "moe.cangku.xingyu/image_clipboard", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() != "readImage") { result->NotImplemented(); return; }
    try {
      const auto bytes = ReadPng();
      if (bytes.empty()) result->Success();
      else result->Success(flutter::EncodableValue(bytes));
    } catch (const std::exception& e) {
      result->Error("clipboard_image", e.what());
    }
  });
  return channel;
}
