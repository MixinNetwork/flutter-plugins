#include "include/desktop_drop/desktop_drop_plugin.h"
#include "desktop_drop_ffi.h"

#include <windows.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <shldisp.h>
#include <shlobj.h>
#include <shlguid.h>
#include <wrl/client.h>
#include "ffi_transport.h"
#include <flutter/standard_message_codec.h>
#include <flutter/method_result_functions.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <cstring>
#include <limits>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using List = flutter::EncodableList;


DWORD NativeOperation(int32_t operation) {
  switch (operation) {
    case 1: return DROPEFFECT_COPY;
    case 2: return DROPEFFECT_MOVE;
    case 3: return DROPEFFECT_LINK;
    default: return DROPEFFECT_NONE;
  }
}

std::vector<std::string> AllowedOperations(DWORD actions) {
  std::vector<std::string> operations;
  if (actions & DROPEFFECT_COPY) operations.emplace_back("copy");
  if (actions & DROPEFFECT_MOVE) operations.emplace_back("move");
  if (actions & DROPEFFECT_LINK) operations.emplace_back("link");
  return operations;
}

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

struct File {
  std::string path;
  std::string name;
  std::optional<bool> directory;
  LONG index = -1;
  CLIPFORMAT format = 0;
  std::optional<uint64_t> length;
  std::string mime_type;
  std::string virtual_path;
};
struct Offer {
  std::vector<File> files;
  std::optional<std::string> text;
  std::optional<std::string> html;
  std::vector<std::string> urls;
  std::vector<std::string> operations;

  std::vector<std::pair<std::string, std::string>> Strings() const {
    std::vector<std::pair<std::string, std::string>> strings;
    if (text) strings.emplace_back("text/plain", *text);
    if (html) strings.emplace_back("text/html", *html);
    if (!urls.empty()) {
      std::string list;
      for (const auto& url : urls) list += url + "\r\n";
      strings.emplace_back("text/uri-list", list);
    }
    return strings;
  }

  Value Encode() const {
    List entries, strings, allowed;
    for (const auto& file : files) {
      Map entry{{Value("name"), Value(file.name)},
        {Value("isDirectory"), file.directory ? Value(*file.directory) : Value()},
        {Value("isPromised"), Value(file.index >= 0)}};
      if (!file.path.empty()) entry[Value("path")] = Value(file.path);
      if (!file.virtual_path.empty()) entry[Value("virtualPath")] = Value(file.virtual_path);
      if (!file.mime_type.empty()) entry[Value("mimeType")] = Value(file.mime_type);
      if (file.index >= 0 || file.format) entry[Value("source")] = Value(static_cast<int64_t>(&file - files.data()));
      entries.emplace_back(entry);
    }
    for (const auto& string : Strings()) strings.emplace_back(Map{
      {Value("mimeType"), Value(string.first)}, {Value("value"), Value(string.second)}});
    for (const auto& operation : operations) allowed.emplace_back(operation);
    return Value(Map{{Value("files"), Value(entries)}, {Value("strings"), Value(strings)},
      {Value("isComplete"), Value(Complete())}, {Value("allowedOperations"), Value(allowed)}});
  }

  bool Complete() const {
    return std::all_of(files.begin(), files.end(), [](const File& file) {
      return !file.name.empty() && file.directory.has_value();
    });
  }


};

CLIPFORMAT Format(const wchar_t* name) {
  return static_cast<CLIPFORMAT>(RegisterClipboardFormatW(name));
}

std::optional<std::vector<uint8_t>> ReadMemory(IDataObject* data, CLIPFORMAT type) {
  FORMATETC format{type, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  STGMEDIUM medium{};
  if (FAILED(data->GetData(&format, &medium))) return std::nullopt;
  std::optional<std::vector<uint8_t>> result;
  if (medium.tymed == TYMED_HGLOBAL) {
    const auto* bytes = static_cast<const uint8_t*>(GlobalLock(medium.hGlobal));
    if (bytes) {
      result = std::vector<uint8_t>(bytes, bytes + GlobalSize(medium.hGlobal));
      GlobalUnlock(medium.hGlobal);
    }
  }
  ReleaseStgMedium(&medium);
  return result;
}

std::string Decode(const char* bytes, int length, UINT code_page) {
  const int count = MultiByteToWideChar(code_page, 0, bytes, length, nullptr, 0);
  if (count <= 0) return {};
  std::wstring wide(count, L'\0');
  MultiByteToWideChar(code_page, 0, bytes, length, wide.data(), count);
  return Utf8(wide);
}

std::optional<std::string> ReadString(IDataObject* data, CLIPFORMAT type, bool wide = true) {
  const auto bytes = ReadMemory(data, type);
  if (!bytes) return std::nullopt;
  if (wide) {
    std::wstring text(bytes->size() / sizeof(wchar_t), L'\0');
    std::memcpy(text.data(), bytes->data(), text.size() * sizeof(wchar_t));
    text.resize(std::find(text.begin(), text.end(), L'\0') - text.begin());
    return Utf8(text);
  }
  const size_t length = std::find(bytes->begin(), bytes->end(), 0) - bytes->begin();
  if (length > static_cast<size_t>((std::numeric_limits<int>::max)())) return std::nullopt;
  return Decode(reinterpret_cast<const char*>(bytes->data()), static_cast<int>(length), CP_ACP);
}

std::optional<std::string> ReadHtml(IDataObject* data) {
  auto bytes = ReadMemory(data, Format(L"HTML Format"));
  if (!bytes) bytes = ReadMemory(data, Format(L"text/html"));
  if (!bytes) return std::nullopt;
  std::string html(bytes->begin(), bytes->end());
  while (!html.empty() && html.back() == '\0') html.pop_back();
  // CF_HTML offsets refer to bytes, not Unicode characters.
  auto offset = [&](const char* key) -> size_t {
    const size_t begin = html.find(key);
    if (begin == std::string::npos) return std::string::npos;
    size_t position = begin + std::strlen(key), value = 0;
    if (position >= html.size() || html[position] < '0' || html[position] > '9') return std::string::npos;
    while (position < html.size() && html[position] >= '0' && html[position] <= '9') {
      const size_t digit = html[position++] - '0';
      if (value > (html.size() - digit) / 10) return std::string::npos;
      value = value * 10 + digit;
    }
    return value;
  };
  const size_t start = offset("StartFragment:"), end = offset("EndFragment:");
  if (start <= end && end <= html.size()) return html.substr(start, end - start);
  return html;
}

template <typename Group, typename Descriptor>
std::vector<File> ReadDescriptors(IDataObject* data, CLIPFORMAT type) {
  const auto bytes = ReadMemory(data, type);
  constexpr size_t header = offsetof(Group, fgd);
  if (!bytes || bytes->size() < header) return {};
  UINT count = 0;
  std::memcpy(&count, bytes->data(), sizeof(count));
  if (count > (bytes->size() - header) / sizeof(Descriptor) || count > static_cast<UINT>((std::numeric_limits<LONG>::max)())) return {};
  std::vector<File> files;
  for (UINT i = 0; i < count; ++i) {
    Descriptor descriptor{};
    std::memcpy(&descriptor, bytes->data() + header + i * sizeof(Descriptor), sizeof(descriptor));
    const bool directory = (descriptor.dwFlags & FD_ATTRIBUTES) &&
        (descriptor.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY);
    const auto* begin = descriptor.cFileName;
    const auto* end = std::find(begin, begin + MAX_PATH, 0);
    std::string name;
    if constexpr (std::is_same_v<Descriptor, FILEDESCRIPTORW>) name = Utf8(std::wstring(begin, end));
    else name = Decode(begin, static_cast<int>(end - begin), CP_ACP);
    const size_t separator = name.find_last_of("\\/");
    File file{"", name.empty() ? "drop" : name.substr(separator == std::string::npos ? 0 : separator + 1), directory};
    file.virtual_path = name;
    file.index = static_cast<LONG>(i);
    if (descriptor.dwFlags & FD_FILESIZE) file.length = (static_cast<uint64_t>(descriptor.nFileSizeHigh) << 32) | descriptor.nFileSizeLow;
    files.push_back(std::move(file));
  }
  return files;
}

std::optional<std::vector<uint8_t>> BitmapBytes(HBITMAP bitmap) {
  BITMAP source{};
  if (!GetObjectW(bitmap, sizeof(source), &source) || source.bmWidth <= 0 || source.bmHeight <= 0) return std::nullopt;
  const uint64_t size = static_cast<uint64_t>(source.bmWidth) * source.bmHeight * 4;
  constexpr size_t header = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
  if (size > (std::numeric_limits<DWORD>::max)() - header) return std::nullopt;
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = source.bmWidth;
  info.bmiHeader.biHeight = source.bmHeight;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  info.bmiHeader.biSizeImage = static_cast<DWORD>(size);
  std::vector<uint8_t> bytes(header + static_cast<size_t>(size));
  HDC dc = CreateCompatibleDC(nullptr);
  if (!dc) return std::nullopt;
  const int rows = GetDIBits(dc, bitmap, 0, static_cast<UINT>(source.bmHeight),
      bytes.data() + header, &info, DIB_RGB_COLORS);
  DeleteDC(dc);
  if (rows != source.bmHeight) return std::nullopt;
  BITMAPFILEHEADER file{};
  file.bfType = 0x4d42;
  file.bfSize = static_cast<DWORD>(bytes.size());
  file.bfOffBits = static_cast<DWORD>(header);
  std::memcpy(bytes.data(), &file, sizeof(file));
  std::memcpy(bytes.data() + sizeof(file), &info.bmiHeader, sizeof(info.bmiHeader));
  return bytes;
}

// Synchronous sources hand over their medium before Drop returns. Readers can
// then consume it without asking the drag source to render the content again.
struct SourceReader {
  STGMEDIUM medium{};
  const uint8_t* memory = nullptr;
  size_t size = 0, offset = 0;
  std::optional<uint64_t> declared_length;
  std::optional<bool> prepared;
  std::shared_ptr<SourceReader> backing;
  std::vector<uint8_t> converted;
  bool exhausted = false, failed = false;
  ~SourceReader() {
    if (memory && medium.tymed == TYMED_HGLOBAL) GlobalUnlock(medium.hGlobal);
    if (medium.tymed) ReleaseStgMedium(&medium);
  }
  bool Acquire(IDataObject* source, const File& file) {
    FORMATETC format{file.format ? file.format : Format(L"FileContents"), nullptr,
      DVASPECT_CONTENT, file.index, static_cast<DWORD>(file.format == CF_BITMAP ? TYMED_GDI : TYMED_ISTREAM | TYMED_HGLOBAL | TYMED_ISTORAGE)};
    declared_length = file.length;
    return SUCCEEDED(source->GetData(&format, &medium));
  }
  bool Prepare() {
    if (!prepared) prepared = PrepareMedium();
    return *prepared;
  }
  bool PrepareMedium() {
    if (medium.tymed == TYMED_ISTREAM && medium.pstm) {
      LARGE_INTEGER zero{};
      const HRESULT seek = medium.pstm->Seek(zero, STREAM_SEEK_SET, nullptr);
      return SUCCEEDED(seek) || seek == E_NOTIMPL || seek == STG_E_INVALIDFUNCTION;
    }
    if (medium.tymed == TYMED_HGLOBAL) {
      size = GlobalSize(medium.hGlobal);
      memory = static_cast<const uint8_t*>(GlobalLock(medium.hGlobal));
      if (!memory && size) return false;
      if (declared_length) {
        if (*declared_length > size) return false;
        size = static_cast<size_t>(*declared_length);
      }
      return true;
    }
    if (medium.tymed == TYMED_GDI && medium.hBitmap) {
      auto bytes = BitmapBytes(medium.hBitmap);
      if (!bytes) return false;
      converted = std::move(*bytes);
    } else if (medium.tymed == TYMED_ISTORAGE && medium.pstg) {
      Microsoft::WRL::ComPtr<ILockBytes> lock;
      Microsoft::WRL::ComPtr<IStorage> storage;
      if (FAILED(CreateILockBytesOnHGlobal(nullptr, TRUE, &lock)) ||
          FAILED(StgCreateDocfileOnILockBytes(lock.Get(), STGM_CREATE | STGM_READWRITE | STGM_SHARE_EXCLUSIVE, 0, &storage)) ||
          FAILED(medium.pstg->CopyTo(0, nullptr, nullptr, storage.Get())) ||
          FAILED(storage->Commit(STGC_DEFAULT))) return false;
      HGLOBAL data = nullptr;
      if (FAILED(GetHGlobalFromILockBytes(lock.Get(), &data))) return false;
      const auto* bytes = static_cast<const uint8_t*>(GlobalLock(data));
      if (!bytes) return false;
      converted.assign(bytes, bytes + GlobalSize(data));
      GlobalUnlock(data);
    } else return false;
    size = converted.size();
    memory = converted.data();
    return true;
  }
  bool Open(IDataObject* source, const File& file) {
    return Acquire(source, file) && Prepare();
  }
  bool Open(const std::shared_ptr<SourceReader>& captured) {
    if (!captured->Prepare()) return false;
    backing = captured;
    if (backing->medium.tymed == TYMED_ISTREAM) {
      Microsoft::WRL::ComPtr<IStream> stream;
      LARGE_INTEGER zero{};
      if (SUCCEEDED(backing->medium.pstm->Clone(&stream)) && stream &&
          SUCCEEDED(stream->Seek(zero, STREAM_SEEK_SET, nullptr))) {
        medium.tymed = TYMED_ISTREAM;
        medium.pstm = stream.Detach();
      }
      // Streams without independent cursors share a lazily filled replay
      // buffer. Only bytes requested by an application read are consumed.
    } else {
      memory = backing->memory;
      size = backing->size;
    }
    return true;
  }
  bool Read(size_t count, std::vector<uint8_t>& bytes) {
    if (backing && !medium.tymed && backing->medium.tymed == TYMED_ISTREAM) {
      if (count > (std::numeric_limits<size_t>::max)() - offset) return false;
      const size_t end = offset + count;
      auto& cache = backing->converted;
      while (cache.size() < end && !backing->exhausted) {
        if (backing->failed) return false;
        std::vector<uint8_t> chunk;
        if (!backing->Read((std::min)(end - cache.size(), size_t{65536}), chunk)) {
          backing->failed = true;
          return false;
        }
        if (chunk.empty()) backing->exhausted = true;
        else cache.insert(cache.end(), chunk.begin(), chunk.end());
      }
      const size_t length = (std::min)(count, cache.size() - offset);
      bytes.assign(cache.begin() + offset, cache.begin() + offset + length);
      offset += length;
    } else if (medium.tymed == TYMED_ISTREAM) {
      bytes.resize(count);
      ULONG received = 0;
      if (FAILED(medium.pstm->Read(bytes.data(), static_cast<ULONG>(count), &received)) || received > count) return false;
      bytes.resize(received);
    } else {
      const size_t length = (std::min)(count, size - offset);
      if (length) bytes.assign(memory + offset, memory + offset + length);
      offset += length;
    }
    return true;
  }
  bool Skip(uint64_t start) {
    if (medium.tymed != TYMED_ISTREAM &&
        !(backing && backing->medium.tymed == TYMED_ISTREAM)) {
      offset = static_cast<size_t>((std::min)(start, static_cast<uint64_t>(size)));
      return true;
    }
    while (start) {
      std::vector<uint8_t> bytes;
      if (!Read(static_cast<size_t>((std::min)(start, uint64_t{65536})), bytes)) return false;
      if (bytes.empty()) break;
      start -= bytes.size();
    }
    return true;
  }
};

int64_t Integer(const Map& args, const char* key, int64_t fallback = -1) {
  const auto it = args.find(Value(key));
  if (it != args.end()) {
    if (const auto* value = std::get_if<int64_t>(&it->second)) return *value;
    if (const auto* value = std::get_if<int32_t>(&it->second)) return *value;
  }
  return fallback;
}

Offer ReadOffer(IDataObject* data) {
  Offer offer;
  FORMATETC format{CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  STGMEDIUM medium{};
  if (SUCCEEDED(data->GetData(&format, &medium))) {
    if (medium.tymed == TYMED_HGLOBAL) {
      const auto drop = reinterpret_cast<HDROP>(medium.hGlobal);
      const UINT count = DragQueryFileW(drop, 0xffffffff, nullptr, 0);
      for (UINT i = 0; i < count; ++i) {
        const UINT length = DragQueryFileW(drop, i, nullptr, 0);
        if (!length) continue;
        std::wstring path(length + 1, L'\0');
        DragQueryFileW(drop, i, path.data(), length + 1);
        path.resize(length);
        const size_t separator = path.find_last_of(L"\\/");
        File file{Utf8(path), Utf8(path.substr(separator == std::wstring::npos ? 0 : separator + 1)), std::nullopt};
        const DWORD attributes = GetFileAttributesW(path.c_str());
        if (attributes != INVALID_FILE_ATTRIBUTES) file.directory = (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
        offer.files.push_back(std::move(file));
      }
    }
    ReleaseStgMedium(&medium);
  }
  if (offer.files.empty()) {
    offer.files = ReadDescriptors<FILEGROUPDESCRIPTORW, FILEDESCRIPTORW>(data, Format(L"FileGroupDescriptorW"));
    if (offer.files.empty()) offer.files = ReadDescriptors<FILEGROUPDESCRIPTORA, FILEDESCRIPTORA>(data, Format(L"FileGroupDescriptor"));
  }
  if (offer.files.empty()) {
    for (const auto& image : {std::make_pair(Format(L"PNG"), "image/png"),
         std::make_pair(static_cast<CLIPFORMAT>(CF_DIBV5), "image/x-dib"),
         std::make_pair(static_cast<CLIPFORMAT>(CF_DIB), "image/x-dib"),
         std::make_pair(static_cast<CLIPFORMAT>(CF_BITMAP), "image/bmp")}) {
      FORMATETC image_format{image.first, nullptr, DVASPECT_CONTENT, -1, static_cast<DWORD>(image.first == CF_BITMAP ? TYMED_GDI : TYMED_HGLOBAL)};
      if (SUCCEEDED(data->QueryGetData(&image_format))) {
        File file{"", image.first == Format(L"PNG") ? "image.png" : image.first == CF_BITMAP ? "image.bmp" : "image.dib", false};
        file.format = image.first;
        file.mime_type = image.second;
        offer.files.push_back(std::move(file));
        break;
      }
    }
  }
  offer.text = ReadString(data, CF_UNICODETEXT);
  if (!offer.text) offer.text = ReadString(data, CF_TEXT, false);
  offer.html = ReadHtml(data);
  auto url = ReadString(data, Format(L"UniformResourceLocatorW"));
  if (!url) url = ReadString(data, Format(L"UniformResourceLocator"), false);
  if (url && !url->empty()) offer.urls.push_back(*url);
  return offer;
}

// Each accepted event owns its source independently of later drags.
struct DroppedSource {
  Microsoft::WRL::ComPtr<IDataObject> data;
  Microsoft::WRL::ComPtr<IDataObjectAsyncCapability> async;
  Offer offer;
  int64_t generation = 0;
  DWORD effect = DROPEFFECT_NONE;
  bool started = false, finished = false;
  std::map<int64_t, std::shared_ptr<SourceReader>> media;
  std::map<int64_t, std::shared_ptr<SourceReader>> readers;

  void Complete(bool success) {
    if (finished) return;
    finished = true;
    // Close media before telling the source that extraction has ended.
    readers.clear();
    media.clear();
    if (started) async->EndOperation(success ? S_OK : E_FAIL, nullptr,
                                    success ? effect : DROPEFFECT_NONE);
    data.Reset();
    async.Reset();
  }
};

bool SupportsAsync(IDataObject* data) {
  Microsoft::WRL::ComPtr<IDataObjectAsyncCapability> capability;
  BOOL enabled = FALSE;
  return SUCCEEDED(data->QueryInterface(IID_PPV_ARGS(capability.GetAddressOf()))) &&
      SUCCEEDED(capability->GetAsyncMode(&enabled)) && enabled;
}

class Destination final : public IDropTarget {
 public:
  Destination(HWND window, int64_t view, FfiTransport* transport)
      : window_(window), view_(view), transport_(transport), context_(dd_bridge_create()) {
    // Keep the source's drag image visible while it is over this window.
    CoCreateInstance(CLSID_DragDropHelper, nullptr, CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(drag_image_.GetAddressOf()));
    status_ = RegisterDragDrop(window_, this);
  }
  int64_t context() const { return context_; }
  HRESULT status() const { return status_; }
  void Shutdown() {
    if (drag_image_active_) drag_image_->DragLeave();
    drag_image_active_ = false;
    drag_image_.Reset();
    ResetSources();
    if (SUCCEEDED(status_)) RevokeDragDrop(window_);
    dd_bridge_destroy(context_);
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
    cached_offer_.reset();
    async_supported_ = SupportsAsync(data);
    offer_.operations = AllowedOperations(OfferedActions());
    Decide(0, position, effect);
    if (drag_image_) {
      POINT point{position.x, position.y};
      drag_image_active_ = SUCCEEDED(drag_image_->DragEnter(window_, data, &point, *effect));
    }
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE DragOver(DWORD, POINTL position, DWORD* effect) override {
    source_actions_ = *effect;
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
    transport_->Invoke("exit", std::make_unique<Value>(Map{
      {Value("view"), Value(view_)}, {Value("session"), Value(session_)},
      {Value("generation"), Value(dd_bridge_generation(context_))}}));
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE Drop(IDataObject* data, DWORD, POINTL position, DWORD* effect) override {
    offer_ = ReadOffer(data);
    cached_offer_.reset();
    async_supported_ = SupportsAsync(data);
    source_actions_ = *effect;
    offer_.operations = AllowedOperations(OfferedActions());
    auto args = Decide(2, position, effect);
    std::shared_ptr<DroppedSource> source;
    if (*effect != DROPEFFECT_NONE) {
      source = std::make_shared<DroppedSource>();
      source->data = data;
      source->generation = dd_bridge_generation(context_);
      source->offer = offer_;
      source->effect = *effect;
      if (!offer_.files.empty() && async_supported_ &&
          SUCCEEDED(data->QueryInterface(IID_PPV_ARGS(source->async.GetAddressOf())))) {
        source->started = SUCCEEDED(source->async->StartOperation(nullptr));
      }
      if (*effect == DROPEFFECT_MOVE && !offer_.files.empty() && !source->started) {
        *effect = DROPEFFECT_NONE;
      } else {
        if (!source->started) {
          for (size_t i = 0; i < source->offer.files.size(); ++i) {
            const auto& file = source->offer.files[i];
            if (!file.path.empty() || file.directory.value_or(false)) continue;
            auto medium = std::make_shared<SourceReader>();
            if (medium->Acquire(data, file)) source->media.emplace(static_cast<int64_t>(i), std::move(medium));
          }
        }
        sources_[session_] = source;
      }
    }
    if (drag_image_active_) {
      POINT point{position.x, position.y};
      drag_image_->Drop(data, &point, *effect);
      drag_image_active_ = false;
    }
    if (*effect != DROPEFFECT_NONE) {
      auto& map = std::get<Map>(*args);
      map[Value("offer")] = offer_.Encode();
      // A reply owns the destination until its accepted source is removed.
      const Microsoft::WRL::ComPtr<Destination> destination(this);
      const auto finish = [destination, source, session = session_](bool success) {
        source->Complete(success);
        const auto found = destination->sources_.find(session);
        if (found != destination->sources_.end() && found->second == source)
          destination->sources_.erase(found);
      };
      transport_->Invoke("drop", std::move(args),
          std::make_unique<flutter::MethodResultFunctions<Value>>(
            [finish](const Value* value) {
              const auto* success = value ? std::get_if<bool>(value) : nullptr;
              finish(success && *success);
            },
            [finish](const std::string&, const std::string&, const Value*) { finish(false); },
            [finish]() { finish(false); }));
    }
    offer_ = Offer{};
    return S_OK;
  }
  void ResetSources() {
    const auto sources = std::move(sources_);
    sources_.clear();
    for (const auto& entry : sources) {
      entry.second->Complete(false);
    }
  }
  void ReadSource(const Map& args, std::unique_ptr<flutter::MethodResult<Value>> result) {
    const auto op_value = args.find(Value("op"));
    const auto* op = op_value == args.end() ? nullptr : std::get_if<std::string>(&op_value->second);
    const auto found_source = sources_.find(Integer(args, "session"));
    const auto source = found_source == sources_.end() ? nullptr : found_source->second;
    const bool current = source && !source->finished &&
        Integer(args, "generation") == source->generation &&
        source->generation == dd_bridge_generation(context_);
    if (!op || !current) { result->Error("source_expired", "Dropped source is no longer available"); return; }
    if (*op == "close") { source->readers.erase(Integer(args, "stream")); result->Success(); return; }
    if (*op == "read") {
      const auto found = source->readers.find(Integer(args, "stream"));
      const int64_t count = Integer(args, "count");
      if (found == source->readers.end() || count <= 0 || count > 65536) {
        result->Error("source_expired", "Dropped reader is no longer available"); return;
      }
      std::vector<uint8_t> bytes;
      const auto reader = found->second;
      if (!reader->Read(static_cast<size_t>(count), bytes)) {
        result->Error("read_failed", "Cannot read dropped content"); return;
      }
      result->Success(Value(bytes)); return;
    }
    const int64_t index = Integer(args, "source");
    if (index < 0 || static_cast<size_t>(index) >= source->offer.files.size()) {
      result->Error("source_expired", "Dropped item is no longer available"); return;
    }
    const auto file = source->offer.files[static_cast<size_t>(index)];
    if (*op == "stat") {
      Map value{{Value("name"), Value(file.name)}};
      if (file.length && *file.length <= static_cast<uint64_t>((std::numeric_limits<int64_t>::max)()))
        value[Value("length")] = Value(static_cast<int64_t>(*file.length));
      result->Success(Value(value)); return;
    }
    if (*op == "open") {
      const int64_t start = Integer(args, "start", 0);
      const auto data = source->data;
      auto reader = std::make_shared<SourceReader>();
      const auto captured = source->media.find(index);
      const bool opened = start >= 0 && (source->started
          ? reader->Open(data.Get(), file)
          : captured != source->media.end() && reader->Open(captured->second));
      if (!opened || !reader->Skip(static_cast<uint64_t>(start))) {
        result->Error("read_failed", "Cannot open dropped content; the source may have expired"); return;
      }
      if (source->finished || source->data.Get() != data.Get() ||
          Integer(args, "generation") != dd_bridge_generation(context_)) {
        result->Error("source_expired", "Dropped source has expired"); return;
      }
      const int64_t id = ++next_reader_;
      source->readers.emplace(id, std::move(reader));
      result->Success(Value(id)); return;
    }
    result->NotImplemented();
  }
 private:
  DWORD OfferedActions() const {
    // A synchronous source can remove files as soon as Drop returns.
    return !offer_.files.empty() && !async_supported_
        ? source_actions_ & ~DROPEFFECT_MOVE : source_actions_;
  }
  std::unique_ptr<Value> Decide(int32_t phase, POINTL position, DWORD* effect) {
    POINT point{position.x, position.y};
    ScreenToClient(window_, &point);
    const double scale = GetDpiForWindow(window_) / 96.0;
    const double x = point.x / scale, y = point.y / scale;
    const DWORD mask = OfferedActions() & (DROPEFFECT_COPY | DROPEFFECT_MOVE | DROPEFFECT_LINK);
    auto request = [&](bool full) {
      Map args{{Value("operationMask"), Value(static_cast<int64_t>(mask))}};
      if (full) {
        if (!cached_offer_) cached_offer_ = std::make_unique<Value>(offer_.Encode());
        args[Value("offer")] = *cached_offer_;
      }
      const auto payload = flutter::StandardMessageCodec::GetInstance().EncodeMessage(Value(args));
      return dd_bridge_decide(context_, session_, phase, x, y,
                              payload->data(), static_cast<int32_t>(payload->size()));
    };
    DDDecision decision = request(phase != 1);
    if (decision.target == -1) decision = request(true);
    const DWORD operation = NativeOperation(decision.operation);
    if (!(OfferedActions() & operation)) { decision.target = 0; decision.operation = 0; }
    *effect = decision.target > 0 ? operation : DROPEFFECT_NONE;
    auto args = std::make_unique<Value>(Map{
      {Value("view"), Value(view_)}, {Value("session"), Value(session_)},
      {Value("generation"), Value(decision.generation)}, {Value("request"), Value(decision.request)},
      {Value("target"), Value(decision.target)}, {Value("phase"), Value(phase)},
      {Value("operation"), Value(decision.operation)},
      {Value("x"), Value(x)}, {Value("y"), Value(y)},
      {Value("operationMask"), Value(static_cast<int64_t>(mask))}});
    transport_->Invoke("feedback", std::make_unique<Value>(*args));
    return args;
  }
  std::atomic<ULONG> references_{1};
  HWND window_;
  int64_t view_;
  FfiTransport* transport_;
  int64_t context_;
  HRESULT status_;
  int64_t session_ = 0;
  DWORD source_actions_ = 0;
  Offer offer_;
  std::unique_ptr<Value> cached_offer_;
  bool async_supported_ = false;
  int64_t next_reader_ = 0;
  std::map<int64_t, std::shared_ptr<DroppedSource>> sources_;
  Microsoft::WRL::ComPtr<IDropTargetHelper> drag_image_;
  bool drag_image_active_ = false;
};

class DesktopDropPlugin final : public flutter::Plugin {
 public:
  explicit DesktopDropPlugin(flutter::PluginRegistrarWindows* registrar, FlutterDesktopMessengerRef messenger)
      : registrar_(registrar), ole_initialized_(SUCCEEDED(OleInitialize(nullptr))) {
    transport_ = std::make_unique<FfiTransport>(messenger);
    transport_->SetHandler([this](const auto& call, auto result) {
      if (call.method_name() == "readSource") {
        const auto* args = std::get_if<Map>(call.arguments());
        const auto found = args ? targets_.find(Integer(*args, "view")) : targets_.end();
        if (!args || found == targets_.end()) { result->Error("source_expired", "Drop destination is no longer available"); return; }
        found->second->ReadSource(*args, std::move(result)); return;
      }
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
        auto* target = new Destination(view->GetNativeWindow(), id, transport_.get());
        if (FAILED(target->status())) {
          target->Shutdown(); target->Release();
          result->Error("register_drag_drop", "Could not register the OLE drop destination"); return;
        }
        found_target = targets_.emplace(id, target).first;
      }
      found_target->second->ResetSources();
      const auto context = found_target->second->context();
      result->Success(Value(Map{{Value("view"), Value(id)}, {Value("context"), Value(context)}}));
    });
  }
  ~DesktopDropPlugin() override {
    transport_->SetHandler(nullptr);
    for (const auto& entry : targets_) { entry.second->Shutdown(); entry.second->Release(); }
    if (ole_initialized_) OleUninitialize();
  }
 private:
  flutter::PluginRegistrarWindows* registrar_;
  bool ole_initialized_;
  std::unique_ptr<FfiTransport> transport_;
  std::map<int64_t, Destination*> targets_;
};
}  // namespace

void DesktopDropPluginRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
  auto* windows = flutter::PluginRegistrarManager::GetInstance()->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  windows->AddPlugin(std::make_unique<DesktopDropPlugin>(windows, FlutterDesktopPluginRegistrarGetMessenger(registrar)));
}
