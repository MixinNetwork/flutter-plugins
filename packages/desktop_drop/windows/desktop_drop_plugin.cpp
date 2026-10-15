#include "include/desktop_drop/desktop_drop_plugin.h"
#include "desktop_drop_ffi.h"

#include <windows.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <shlguid.h>
#include <wrl/client.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <atomic>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using List = flutter::EncodableList;
using Channel = flutter::MethodChannel<Value>;

std::string Utf8(const std::wstring& input) {
  if (input.empty()) return {};
  const int count = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, input.data(),
      static_cast<int>(input.size()), nullptr, 0, nullptr, nullptr);
  if (count <= 0) return {};
  std::string output(count, '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, input.data(),
      static_cast<int>(input.size()), output.data(), count, nullptr, nullptr);
  return output;
}

std::string Quote(const std::string& input) {
  std::string output = "\"";
  for (unsigned char c : input) {
    if (c == '"' || c == '\\') { output += '\\'; output += static_cast<char>(c); }
    else if (c < 32) {
      const char* hex = "0123456789abcdef";
      output += "\\u00"; output += hex[c >> 4]; output += hex[c & 15];
    } else output += static_cast<char>(c);
  }
  return output + "\"";
}

struct File {
  std::string path;
  std::string name;
  std::optional<bool> directory;
};
struct Offer {
  std::vector<File> files;
  std::optional<std::string> text;
  std::vector<std::string> urls;

  Value Encode() const {
    List types, entries, links;
    if (!files.empty()) types.emplace_back("file");
    if (text) types.emplace_back("text");
    if (!urls.empty()) types.emplace_back("url");
    for (const auto& file : files) entries.emplace_back(Map{
      {Value("path"), Value(file.path)}, {Value("name"), Value(file.name)},
      {Value("isDirectory"), file.directory ? Value(*file.directory) : Value()},
      {Value("isPromised"), Value(false)}});
    for (const auto& url : urls) links.emplace_back(url);
    return Value(Map{{Value("types"), Value(types)}, {Value("files"), Value(entries)},
      {Value("text"), text ? Value(*text) : Value()}, {Value("urls"), Value(links)},
      {Value("isComplete"), Value(true)}});
  }

  std::string Json() const {
    std::string types = "[", entries = "[", links = "[";
    auto append = [](std::string& list, const std::string& value) {
      if (list.size() > 1) list += ",";
      list += value;
    };
    if (!files.empty()) append(types, "\"file\"");
    if (text) append(types, "\"text\"");
    if (!urls.empty()) append(types, "\"url\"");
    for (const auto& file : files) {
      const std::string directory = file.directory ? (*file.directory ? "true" : "false") : "null";
      append(entries, "{\"path\":" + Quote(file.path) + ",\"name\":" + Quote(file.name) +
        ",\"isDirectory\":" + directory + ",\"isPromised\":false}");
    }
    for (const auto& url : urls) append(links, Quote(url));
    return "{\"types\":" + types + "],\"files\":" + entries + "],\"text\":" +
      (text ? Quote(*text) : "null") + ",\"urls\":" + links + "],\"isComplete\":true}";
  }
};

std::optional<std::string> ReadString(IDataObject* data, CLIPFORMAT type) {
  FORMATETC format{type, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  STGMEDIUM medium{};
  if (FAILED(data->GetData(&format, &medium))) return std::nullopt;
  std::optional<std::string> result;
  const auto* text = static_cast<const wchar_t*>(GlobalLock(medium.hGlobal));
  if (text) {
    const size_t length = GlobalSize(medium.hGlobal) / sizeof(wchar_t);
    const auto* end = std::find(text, text + length, L'\0');
    result = Utf8(std::wstring(text, end));
    GlobalUnlock(medium.hGlobal);
  }
  ReleaseStgMedium(&medium);
  return result;
}

Offer ReadOffer(IDataObject* data, bool metadata = false) {
  Offer offer;
  FORMATETC format{CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  STGMEDIUM medium{};
  if (SUCCEEDED(data->GetData(&format, &medium))) {
    const auto drop = reinterpret_cast<HDROP>(medium.hGlobal);
    const UINT count = DragQueryFileW(drop, 0xffffffff, nullptr, 0);
    for (UINT i = 0; i < count; ++i) {
      const UINT length = DragQueryFileW(drop, i, nullptr, 0);
      std::wstring path(length + 1, L'\0');
      DragQueryFileW(drop, i, path.data(), length + 1);
      path.resize(length);
      const size_t separator = path.find_last_of(L"\\/");
      File file{Utf8(path), Utf8(path.substr(separator == std::wstring::npos ? 0 : separator + 1)), std::nullopt};
      if (metadata) {
        const DWORD attributes = GetFileAttributesW(path.c_str());
        if (attributes != INVALID_FILE_ATTRIBUTES) file.directory = (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
      }
      offer.files.push_back(std::move(file));
    }
    ReleaseStgMedium(&medium);
  }
  offer.text = ReadString(data, CF_UNICODETEXT);
  const auto url = ReadString(data, static_cast<CLIPFORMAT>(RegisterClipboardFormatW(L"UniformResourceLocatorW")));
  if (url && !url->empty()) offer.urls.push_back(*url);
  return offer;
}

class Destination final : public IDropTarget {
 public:
  Destination(HWND window, int64_t view, Channel* channel)
      : window_(window), view_(view), channel_(channel), functions_(dd_bridge_create()) {
    // Keep the source's drag image visible while it is over this window.
    CoCreateInstance(CLSID_DragDropHelper, nullptr, CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(drag_image_.GetAddressOf()));
    status_ = RegisterDragDrop(window_, this);
  }
  const DDBridgeFunctions& functions() const { return functions_; }
  HRESULT status() const { return status_; }
  void Shutdown() {
    if (drag_image_active_) drag_image_->DragLeave();
    drag_image_active_ = false;
    drag_image_.Reset();
    if (SUCCEEDED(status_)) RevokeDragDrop(window_);
    dd_bridge_destroy(functions_.context);
  }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** out) override {
    if (!out) return E_POINTER;
    *out = nullptr;
    if (iid == IID_IUnknown || iid == IID_IDropTarget) {
      *out = static_cast<IDropTarget*>(this); AddRef(); return S_OK;
    }
    return E_NOINTERFACE;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
  ULONG STDMETHODCALLTYPE Release() override {
    const ULONG count = --references_; if (!count) delete this; return count;
  }
  HRESULT STDMETHODCALLTYPE DragEnter(IDataObject* data, DWORD, POINTL position, DWORD* effect) override {
    ++session_;
    source_actions_ = *effect;
    offer_ = ReadOffer(data);
    Decide(0, position, effect);
    if (drag_image_) {
      POINT point{position.x, position.y};
      drag_image_active_ = SUCCEEDED(drag_image_->DragEnter(window_, data, &point, *effect));
    }
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE DragOver(DWORD, POINTL position, DWORD* effect) override {
    Decide(1, position, effect);
    if (drag_image_active_) {
      POINT point{position.x, position.y};
      drag_image_->DragOver(&point, *effect);
    }
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE DragLeave() override {
    if (drag_image_active_) drag_image_->DragLeave();
    drag_image_active_ = false;
    channel_->InvokeMethod("exit", std::make_unique<Value>(Map{
      {Value("view"), Value(view_)}, {Value("session"), Value(session_)},
      {Value("generation"), Value(dd_bridge_generation(functions_.context))}}));
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE Drop(IDataObject* data, DWORD, POINTL position, DWORD* effect) override {
    offer_ = ReadOffer(data, true);
    auto args = Decide(2, position, effect);
    if (drag_image_active_) {
      POINT point{position.x, position.y};
      drag_image_->Drop(data, &point, *effect);
      drag_image_active_ = false;
    }
    if (*effect == DROPEFFECT_COPY) channel_->InvokeMethod("drop", std::move(args));
    return S_OK;
  }
 private:
  std::unique_ptr<Value> Decide(int32_t phase, POINTL position, DWORD* effect) {
    POINT point{position.x, position.y};
    ScreenToClient(window_, &point);
    const double scale = GetDpiForWindow(window_) / 96.0;
    const double x = point.x / scale, y = point.y / scale;
    DDDecision decision = dd_bridge_decide(functions_.context, session_, phase, x, y, offer_.Json().c_str());
    if (!(source_actions_ & DROPEFFECT_COPY)) decision.target = 0;
    *effect = decision.target > 0 ? DROPEFFECT_COPY : DROPEFFECT_NONE;
    auto args = std::make_unique<Value>(Map{
      {Value("view"), Value(view_)}, {Value("session"), Value(session_)},
      {Value("generation"), Value(decision.generation)}, {Value("request"), Value(decision.request)},
      {Value("target"), Value(decision.target)}, {Value("phase"), Value(phase)},
      {Value("x"), Value(x)}, {Value("y"), Value(y)}, {Value("offer"), offer_.Encode()}});
    channel_->InvokeMethod("feedback", std::make_unique<Value>(*args));
    return args;
  }
  std::atomic<ULONG> references_{1};
  HWND window_;
  int64_t view_;
  Channel* channel_;
  DDBridgeFunctions functions_;
  HRESULT status_;
  int64_t session_ = 0;
  DWORD source_actions_ = 0;
  Offer offer_;
  Microsoft::WRL::ComPtr<IDropTargetHelper> drag_image_;
  bool drag_image_active_ = false;
};

class DesktopDropPlugin final : public flutter::Plugin {
 public:
  explicit DesktopDropPlugin(flutter::PluginRegistrarWindows* registrar)
      : registrar_(registrar), ole_initialized_(SUCCEEDED(OleInitialize(nullptr))) {
    channel_ = std::make_unique<Channel>(registrar->messenger(), "desktop_drop", &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() != "initialize") { result->NotImplemented(); return; }
      const auto* args = std::get_if<Map>(call.arguments());
      const auto found = args ? args->find(Value("view")) : Map::const_iterator{};
      if (!args || found == args->end()) { result->Error("invalid_view", "Expected a Flutter view ID"); return; }
      int64_t id;
      if (const auto* value = std::get_if<int32_t>(&found->second)) id = *value;
      else if (const auto* wide_value = std::get_if<int64_t>(&found->second)) id = *wide_value;
      else { result->Error("invalid_view", "Expected a Flutter view ID"); return; }
      auto view = registrar_->GetViewById(id);
      if (!view) { result->Error("unsupported_view", "Flutter view is not attached"); return; }
      auto found_target = targets_.find(id);
      if (found_target == targets_.end()) {
        auto* target = new Destination(view->GetNativeWindow(), id, channel_.get());
        if (FAILED(target->status())) {
          target->Shutdown(); target->Release();
          result->Error("register_drag_drop", "Could not register the OLE drop destination"); return;
        }
        found_target = targets_.emplace(id, target).first;
      }
      const auto& functions = found_target->second->functions();
      result->Success(Value(Map{{Value("view"), Value(id)}, {Value("context"), Value(functions.context)},
        {Value("register"), Value(static_cast<int64_t>(functions.register_callback))},
        {Value("complete"), Value(static_cast<int64_t>(functions.complete))},
        {Value("unregister"), Value(static_cast<int64_t>(functions.unregister_callback))}}));
    });
  }
  ~DesktopDropPlugin() override {
    channel_->SetMethodCallHandler(nullptr);
    for (const auto& entry : targets_) { entry.second->Shutdown(); entry.second->Release(); }
    if (ole_initialized_) OleUninitialize();
  }
 private:
  flutter::PluginRegistrarWindows* registrar_;
  bool ole_initialized_;
  std::unique_ptr<Channel> channel_;
  std::map<int64_t, Destination*> targets_;
};
}  // namespace

void DesktopDropPluginRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
  auto* windows = flutter::PluginRegistrarManager::GetInstance()->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  windows->AddPlugin(std::make_unique<DesktopDropPlugin>(windows));
}
