#pragma once
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <windows.h>
#include <shellapi.h>
#include <memory>
class SystemNotifications {
 public:
  SystemNotifications(flutter::BinaryMessenger* messenger, HWND window);
  ~SystemNotifications();
  bool Handle(UINT message, LPARAM data);
 private:
  void Remove();
  HWND window_;
  NOTIFYICONDATAW icon_{};
  bool enabled_ = false, installed_ = false;
  int owner_ = 0;
  flutter::EncodableMap pending_, latest_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
