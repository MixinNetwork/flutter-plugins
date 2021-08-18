#include "include/desktop_drop/desktop_drop_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>
#include <algorithm>

namespace {

using FlutterMethodChannel = std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>;


using namespace std::literals::string_literals;

std::string ws2s(const std::wstring &wstr) {
  if (wstr.empty()) {
    return {};
  }
  size_t pos;
  size_t begin = 0;
  std::string ret;

  int size;
  pos = wstr.find(static_cast<wchar_t>(0), begin);
  while (pos != std::wstring::npos && begin < wstr.length()) {
    std::wstring segment = std::wstring(&wstr[begin], pos - begin);
    size = WideCharToMultiByte(CP_UTF8,
                               WC_ERR_INVALID_CHARS,
                               &segment[0],
                               (int) segment.size(),
                               nullptr,
                               0,
                               nullptr,
                               nullptr);
    std::string converted = std::string(size, 0);
    WideCharToMultiByte(CP_UTF8,
                        WC_ERR_INVALID_CHARS,
                        &segment[0],
                        (int) segment.size(),
                        &converted[0],
                        (int) converted.size(),
                        nullptr,
                        nullptr);
    ret.append(converted);
    ret.append({0});
    begin = pos + 1;
    pos = wstr.find(static_cast<wchar_t>(0), begin);
  }
  if (begin <= wstr.length()) {
    std::wstring segment = std::wstring(&wstr[begin], wstr.length() - begin);
    size =
        WideCharToMultiByte(CP_UTF8,
                            WC_ERR_INVALID_CHARS,
                            &segment[0],
                            (int) segment.size(),
                            nullptr,
                            0,
                            nullptr,
                            nullptr);
    std::string converted = std::string(size, 0);
    WideCharToMultiByte(CP_UTF8,
                        WC_ERR_INVALID_CHARS,
                        &segment[0],
                        (int) segment.size(),
                        &converted[0],
                        (int) converted.size(),
                        nullptr,
                        nullptr);
    ret.append(converted);
  }

  return ret;
}
class DesktopDropPlugin : public flutter::Plugin, public IDropTarget {

 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  DesktopDropPlugin(HWND window_handle, FlutterMethodChannel channel);

  ~DesktopDropPlugin() override;

  HRESULT DragEnter(IDataObject *pDataObj, DWORD grfKeyState, POINTL pt, DWORD *pdwEffect) override;
  HRESULT DragOver(DWORD grfKeyState, POINTL pt, DWORD *pdwEffect) override;
  HRESULT DragLeave() override;
  HRESULT Drop(IDataObject *pDataObj, DWORD grfKeyState, POINTL pt, DWORD *pdwEffect) override;

  HRESULT QueryInterface(const IID &riid, void **ppvObject) override;
  ULONG AddRef() override;
  ULONG Release() override;

 private:

  HWND window_handle_;

  FlutterMethodChannel channel_;

  LONG ref_count_;

  bool need_revoke_ole_initialize_;

};

// static
void DesktopDropPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "desktop_drop",
          &flutter::StandardMethodCodec::GetInstance());

  HWND hwnd;
  if (registrar->GetView()) {
    hwnd = registrar->GetView()->GetNativeWindow();
  }

  registrar->GetView();

  channel->SetMethodCallHandler([](const auto &call, auto result) {
    result->NotImplemented();
  });

  auto plugin = std::make_unique<DesktopDropPlugin>(hwnd, std::move(channel));

  registrar->AddPlugin(std::move(plugin));
}

DesktopDropPlugin::DesktopDropPlugin(HWND window_handle, FlutterMethodChannel channel)
    : window_handle_(window_handle),
      ref_count_(0),
      channel_(std::move(channel)),
      need_revoke_ole_initialize_(false) {
  OleInitialize(nullptr);
  auto ret = RegisterDragDrop(window_handle_, this);
  if (ret == E_OUTOFMEMORY) {
    OleInitialize(nullptr);
    ret = RegisterDragDrop(window_handle_, this);
    if (ret == 0) {
      need_revoke_ole_initialize_ = true;
    }
  }

  if (ret != 0) {
    std::cout << "RegisterDragDrop failed: " << ret << std::endl;
  }

}

DesktopDropPlugin::~DesktopDropPlugin() {
  RevokeDragDrop(window_handle_);
  if (need_revoke_ole_initialize_) {
    OleUninitialize();
  }
}

HRESULT DesktopDropPlugin::DragEnter(IDataObject *pDataObj, DWORD grfKeyState, POINTL pt, DWORD *pdwEffect) {
  POINT point = {pt.x, pt.y};
  ScreenToClient(window_handle_, &point);
  channel_->InvokeMethod("entered", std::make_unique<flutter::EncodableValue>(
      flutter::EncodableList{
          flutter::EncodableValue(double(point.x)),
          flutter::EncodableValue(double(point.y))
      }
  ));
  return 0;
}

HRESULT DesktopDropPlugin::DragOver(DWORD grfKeyState, POINTL pt, DWORD *pdwEffect) {
  POINT point = {pt.x, pt.y};
  ScreenToClient(window_handle_, &point);
  channel_->InvokeMethod("updated", std::make_unique<flutter::EncodableValue>(
      flutter::EncodableList{
          flutter::EncodableValue(double(point.x)),
          flutter::EncodableValue(double(point.y))
      }
  ));
  return 0;
}

HRESULT DesktopDropPlugin::DragLeave() {
  channel_->InvokeMethod("exited", std::make_unique<flutter::EncodableValue>());
  return 0;
}

HRESULT DesktopDropPlugin::Drop(IDataObject *pDataObj, DWORD grfKeyState, POINTL pt, DWORD *pdwEffect) {

  flutter::EncodableList list = {};

  // construct a FORMATETC object
  FORMATETC fmtetc = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  STGMEDIUM stgmed;

  // See if the dataobject contains any TEXT stored as a HGLOBAL
  if (pDataObj->QueryGetData(&fmtetc) == S_OK) {
    // Yippie! the data is there, so go get it!
    if (pDataObj->GetData(&fmtetc, &stgmed) == S_OK) {
      // we asked for the data as a HGLOBAL, so access it appropriately
      PVOID data = GlobalLock(stgmed.hGlobal);
      if (data != nullptr) {
        auto files = DragQueryFile(reinterpret_cast<HDROP>(data), 0xFFFFFFFF, nullptr, 0);
        for (unsigned int i = 0; i < files; ++i) {
          TCHAR filename[MAX_PATH];
          DragQueryFile(reinterpret_cast<HDROP>(data), i, filename, sizeof(TCHAR) * MAX_PATH);
          std::wstring wide(filename);
          std::string path = ws2s(wide);
          std::cout << "done: " << path << std::endl;
          list.push_back(flutter::EncodableValue(path));
        }
        GlobalUnlock(stgmed.hGlobal);
      }

      // release the data using the COM API
      ReleaseStgMedium(&stgmed);
    }
  }
  channel_->InvokeMethod("performOperation", std::make_unique<flutter::EncodableValue>(list));

  return 0;
}

HRESULT DesktopDropPlugin::QueryInterface(const IID &iid, void **ppvObject) {
  if (iid == IID_IDropTarget || iid == IID_IUnknown) {
    AddRef();
    *ppvObject = this;
    return S_OK;
  } else {
    *ppvObject = nullptr;
    return E_NOINTERFACE;
  }
}

ULONG DesktopDropPlugin::AddRef() {
  return InterlockedIncrement(&ref_count_);
}

ULONG DesktopDropPlugin::Release() {
  LONG count = InterlockedDecrement(&ref_count_);

  if (count == 0) {
    delete this;
    return 0;
  } else {
    return count;
  }
}

}  // namespace

void DesktopDropPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  DesktopDropPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));

}
