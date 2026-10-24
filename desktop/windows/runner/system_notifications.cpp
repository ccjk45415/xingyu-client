#include "system_notifications.h"
#include "patch_bootstrap.h"
#include "resource.h"
#include <flutter/standard_method_codec.h>
#include <string>

namespace {
constexpr UINT kCallback = WM_APP + 91;
std::string Text(const flutter::EncodableMap& map, const char* key) {
  auto it=map.find(flutter::EncodableValue(key));
  if(it==map.end()) return {};
  auto p=std::get_if<std::string>(&it->second); return p?*p:std::string();
}
int Number(const flutter::EncodableMap& map, const char* key) {
  auto it=map.find(flutter::EncodableValue(key)); if(it==map.end())return 0;
  if(auto p=std::get_if<int32_t>(&it->second))return *p;
  if(auto p=std::get_if<int64_t>(&it->second))return static_cast<int>(*p);
  return 0;
}
std::wstring Wide(const std::string& value) {
  int size=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),nullptr,0);
  std::wstring out(size,L'\0');
  if(size)MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),out.data(),size);
  return out;
}
}
SystemNotifications::SystemNotifications(flutter::BinaryMessenger* messenger, HWND window):window_(window) {
  channel_=std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(messenger,"moe.cangku.xingyu/notifications",&flutter::StandardMethodCodec::GetInstance());
  icon_.cbSize=sizeof(icon_); icon_.hWnd=window; icon_.uID=73105;
  icon_.uCallbackMessage=kCallback; icon_.hIcon=LoadIcon(GetModuleHandle(nullptr),MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(icon_.szTip,L"仓库 · 星屿");
  channel_->SetMethodCallHandler([this](const auto& call,auto result) {
    using V=flutter::EncodableValue;
    if(call.method_name()=="status") {result->Success(V(flutter::EncodableMap{{V("supported"),V(true)},{V("granted"),V(true)},{V("patchReady"),V(PatchBootstrapReady())}}));return;}
    if(call.method_name()=="request") {result->Success(V(true));return;}
    if(call.method_name()=="settings") {ShellExecuteW(nullptr,L"open",L"ms-settings:notifications",nullptr,nullptr,SW_SHOWNORMAL);result->Success();return;}
    if(call.method_name()=="takeOpen") {result->Success(V(pending_));pending_.clear();return;}
    auto args=call.arguments()?std::get_if<flutter::EncodableMap>(call.arguments()):nullptr;
    if(!args){result->Error("notification","Invalid arguments");return;}
    if(call.method_name()=="configure") {
      int owner=Number(*args,"uid"); auto it=args->find(V("enabled"));auto on=it==args->end()?nullptr:std::get_if<bool>(&it->second);
      if(owner!=owner_) {pending_.clear();latest_.clear();Remove();}
      owner_=owner;enabled_=on&&*on&&owner>0;
      if(!enabled_) {pending_.clear();latest_.clear();Remove();}
      result->Success();return;
    }
    if(call.method_name()=="show") {
      if(!enabled_ || Number(*args,"uid")!=owner_){result->Success();return;}
      if(!installed_) {icon_.uFlags=NIF_ICON|NIF_MESSAGE|NIF_TIP;installed_=Shell_NotifyIconW(NIM_ADD,&icon_)!=FALSE;}
      if(!installed_){result->Error("notification","系统通知区域暂不可用");return;}
      latest_=*args;
      // Retain only routing metadata after delivery.
      latest_.erase(V("title"));latest_.erase(V("body"));
      wcsncpy_s(icon_.szInfoTitle,Wide(Text(*args,"title")).c_str(),_TRUNCATE);
      wcsncpy_s(icon_.szInfo,Wide(Text(*args,"body")).c_str(),_TRUNCATE);
      icon_.uFlags=NIF_INFO;icon_.dwInfoFlags=NIIF_INFO|NIIF_RESPECT_QUIET_TIME;
      const bool sent=Shell_NotifyIconW(NIM_MODIFY,&icon_)!=FALSE;
      SecureZeroMemory(icon_.szInfo,sizeof(icon_.szInfo));SecureZeroMemory(icon_.szInfoTitle,sizeof(icon_.szInfoTitle));
      if(sent)result->Success();else result->Error("notification","系统暂未显示通知");return;
    }
    result->NotImplemented();
  });
}
void SystemNotifications::Remove(){if(installed_)Shell_NotifyIconW(NIM_DELETE,&icon_);installed_=false;}
SystemNotifications::~SystemNotifications(){Remove();}
bool SystemNotifications::Handle(UINT message, LPARAM data) {
  if(message!=kCallback)return false;
  if(data==NIN_BALLOONUSERCLICK || data==WM_LBUTTONUP) {
    pending_=latest_;ShowWindow(window_,SW_RESTORE);SetForegroundWindow(window_);
    channel_->InvokeMethod("opened",nullptr);
  }
  return true;
}
