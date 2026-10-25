#include "system_proxy.h"
#include <windows.h>
#include <winhttp.h>
#include <flutter/standard_method_codec.h>
#include "utils.h"

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> RegisterSystemProxy(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "moe.cangku.xingyu/platform", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() != "proxy") { result->NotImplemented(); return; }
    WINHTTP_CURRENT_USER_IE_PROXY_CONFIG config{};
    flutter::EncodableMap value;
    if (WinHttpGetIEProxyConfigForCurrentUser(&config)) {
      if (config.lpszProxy) value[flutter::EncodableValue("server")] = flutter::EncodableValue(Utf8FromUtf16(config.lpszProxy));
      if (config.lpszProxyBypass) value[flutter::EncodableValue("bypass")] = flutter::EncodableValue(Utf8FromUtf16(config.lpszProxyBypass));
    }
    if (config.lpszProxy) GlobalFree(config.lpszProxy);
    if (config.lpszProxyBypass) GlobalFree(config.lpszProxyBypass);
    if (config.lpszAutoConfigUrl) GlobalFree(config.lpszAutoConfigUrl);
    result->Success(flutter::EncodableValue(value));
  });
  return channel;
}
