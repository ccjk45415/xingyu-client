#include "editor_ime.h"
#include <flutter/standard_method_codec.h>
#include <commctrl.h>
#include <imm.h>
#include <algorithm>
#include <cmath>

namespace {
constexpr UINT_PTR kSubclass = 0x58494d45;
constexpr UINT kApplyCaret = WM_APP + 0x34d;
bool Number(const flutter::EncodableMap& map, const char* key, double* out) {
  auto at = map.find(flutter::EncodableValue(key));
  if (at == map.end()) return false;
  auto number = std::get_if<double>(&at->second);
  if (!number || !std::isfinite(*number) || std::abs(*number) > 1000000) return false;
  *out = *number;
  return true;
}
}
EditorIme::EditorIme(flutter::BinaryMessenger* messenger, HWND view) : view_(view) {
  SetWindowSubclass(view_, WindowProc, kSubclass, reinterpret_cast<DWORD_PTR>(this));
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "moe.cangku.xingyu/editor_ime", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "clearCaret") {
      active_ = false;
      result->Success();
      return;
    }
    if (call.method_name() != "setCaret") { result->NotImplemented(); return; }
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args || !Number(*args, "x", &x_) || !Number(*args, "y", &y_) ||
        !Number(*args, "width", &width_) || !Number(*args, "height", &height_) ||
        width_ < 0 || height_ <= 0) {
      active_ = false;
      result->Error("geometry", "Invalid caret geometry");
      return;
    }
    active_ = true;
    Update();
    // Apply again after the current engine platform-message batch completes.
    PostMessage(view_, kApplyCaret, 0, 0);
    result->Success();
  });
}
EditorIme::~EditorIme() {
  channel_->SetMethodCallHandler(nullptr);
  if (IsWindow(view_)) RemoveWindowSubclass(view_, WindowProc, kSubclass);
}
void EditorIme::Update() {
  if (!active_ || updating_ || GetFocus() != view_) return;
  RECT client{};
  if (!GetClientRect(view_, &client) || client.right <= 0 || client.bottom <= 0) return;
  const double scale = GetDpiForWindow(view_) / 96.0;
  // RenderEditable coordinates already include both editor and page scroll.
  // Convert logical coordinates once and keep a hidden caret inside the view.
  const LONG left = std::clamp<LONG>(static_cast<LONG>(std::lround(x_ * scale)), 0, client.right - 1);
  const LONG top = std::clamp<LONG>(static_cast<LONG>(std::lround(y_ * scale)), 0, client.bottom - 1);
  const LONG right = std::clamp<LONG>(left + static_cast<LONG>(std::lround(width_ * scale)), left + 1, client.right);
  const LONG bottom = std::clamp<LONG>(top + static_cast<LONG>(std::lround(height_ * scale)), top + 1, client.bottom);
  HIMC context = ImmGetContext(view_);
  if (!context) return;
  updating_ = true;
  SetCaretPos(left, bottom);
  COMPOSITIONFORM composition = {CFS_POINT, {left, top}, {0, 0, 0, 0}};
  ImmSetCompositionWindow(context, &composition);
  CANDIDATEFORM candidate = {0, CFS_EXCLUDE, {left, bottom}, {left, top, right, bottom}};
  ImmSetCandidateWindow(context, &candidate);
  ImmReleaseContext(view_, context);
  updating_ = false;
}
LRESULT CALLBACK EditorIme::WindowProc(HWND hwnd, UINT message, WPARAM wp, LPARAM lp, UINT_PTR id, DWORD_PTR data) {
  auto* self = reinterpret_cast<EditorIme*>(data);
  if (message == kApplyCaret) { self->Update(); return 0; }
  // Let the engine process composition normally, then correct candidate geometry.
  const LRESULT result = DefSubclassProc(hwnd, message, wp, lp);
  if (message == WM_IME_STARTCOMPOSITION || message == WM_IME_COMPOSITION ||
      message == WM_IME_NOTIFY || message == WM_SETFOCUS || message == WM_SIZE || message == WM_DPICHANGED) self->Update();
  if (message == WM_NCDESTROY) RemoveWindowSubclass(hwnd, WindowProc, id);
  return result;
}
