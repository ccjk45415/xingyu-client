#ifndef RUNNER_EDITOR_IME_H_
#define RUNNER_EDITOR_IME_H_
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include <memory>

// Owns a subclass of the Flutter child window; never intercepts input text.
class EditorIme {
 public:
  EditorIme(flutter::BinaryMessenger* messenger, HWND view);
  ~EditorIme();
 private:
  static LRESULT CALLBACK WindowProc(HWND, UINT, WPARAM, LPARAM, UINT_PTR, DWORD_PTR);
  void Update();
  HWND view_;
  bool active_ = false, updating_ = false;
  double x_ = 0, y_ = 0, width_ = 0, height_ = 0;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
#endif
