#include "title_bar_accessibility.h"

#include <UIAutomation.h>

#include <atomic>
#include <utility>

namespace dww {

struct TitleBarAccessibility::State {
  HWND window = nullptr;
  std::function<std::vector<AccessibleButton>()> buttons;
  std::function<void(int)> invoke;
  bool connected = true;
  // Owned by TitleBarAccessibility; the providers refer back to it.
  IRawElementProviderSimple* root = nullptr;
};

namespace {

using State = TitleBarAccessibility::State;

bool Visible(const AccessibleButton& button) {
  return !IsRectEmpty(&button.rect);
}

// The visible button after (|step| 1) or before (|step| -1) |index|, or -1.
int VisibleFrom(const std::vector<AccessibleButton>& buttons, int index,
                int step) {
  for (int i = index + step; i >= 0 && i < static_cast<int>(buttons.size());
       i += step) {
    if (Visible(buttons[i])) return i;
  }
  return -1;
}

RECT ScreenRect(HWND window, RECT rect) {
  MapWindowPoints(window, HWND_DESKTOP, reinterpret_cast<POINT*>(&rect), 2);
  return rect;
}

IRawElementProviderFragment* CreateButton(std::shared_ptr<State> state,
                                          int index);

class Button : public IRawElementProviderSimple,
               public IRawElementProviderFragment,
               public IInvokeProvider {
 public:
  Button(std::shared_ptr<State> state, int index)
      : state_(std::move(state)), index_(index) {}

  ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
  ULONG STDMETHODCALLTYPE Release() override {
    const ULONG references = --references_;
    if (references == 0) delete this;
    return references;
  }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override {
    if (iid == __uuidof(IUnknown) ||
        iid == __uuidof(IRawElementProviderSimple)) {
      *object = static_cast<IRawElementProviderSimple*>(this);
    } else if (iid == __uuidof(IRawElementProviderFragment)) {
      *object = static_cast<IRawElementProviderFragment*>(this);
    } else if (iid == __uuidof(IInvokeProvider)) {
      *object = static_cast<IInvokeProvider*>(this);
    } else {
      *object = nullptr;
      return E_NOINTERFACE;
    }
    AddRef();
    return S_OK;
  }

  // IRawElementProviderSimple
  HRESULT STDMETHODCALLTYPE
  get_ProviderOptions(ProviderOptions* options) override {
    *options = static_cast<ProviderOptions>(ProviderOptions_ServerSideProvider |
                                            ProviderOptions_UseComThreading);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetPatternProvider(PATTERNID pattern,
                                               IUnknown** provider) override {
    *provider = nullptr;
    if (pattern == UIA_InvokePatternId) {
      *provider = static_cast<IInvokeProvider*>(this);
      AddRef();
    }
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetPropertyValue(PROPERTYID property,
                                             VARIANT* value) override {
    value->vt = VT_EMPTY;
    AccessibleButton button;
    if (!Current(&button)) return UIA_E_ELEMENTNOTAVAILABLE;
    switch (property) {
      case UIA_ControlTypePropertyId:
        value->vt = VT_I4;
        value->lVal = UIA_ButtonControlTypeId;
        break;
      case UIA_NamePropertyId:
        value->vt = VT_BSTR;
        value->bstrVal = SysAllocString(button.name.c_str());
        break;
      case UIA_AutomationIdPropertyId:
        value->vt = VT_BSTR;
        value->bstrVal = SysAllocString(button.automation_id);
        break;
      case UIA_IsEnabledPropertyId:
        value->vt = VT_BOOL;
        value->boolVal = button.enabled ? VARIANT_TRUE : VARIANT_FALSE;
        break;
      // Pointer-only, like the native caption buttons.
      case UIA_IsKeyboardFocusablePropertyId:
        value->vt = VT_BOOL;
        value->boolVal = VARIANT_FALSE;
        break;
    }
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE
  get_HostRawElementProvider(IRawElementProviderSimple** provider) override {
    *provider = nullptr;
    return S_OK;
  }

  // IRawElementProviderFragment
  HRESULT STDMETHODCALLTYPE
  Navigate(NavigateDirection direction,
           IRawElementProviderFragment** element) override {
    *element = nullptr;
    if (!state_->connected) return UIA_E_ELEMENTNOTAVAILABLE;
    switch (direction) {
      case NavigateDirection_Parent:
        return state_->root->QueryInterface(IID_PPV_ARGS(element));
      case NavigateDirection_NextSibling:
      case NavigateDirection_PreviousSibling: {
        const int sibling =
            VisibleFrom(state_->buttons(), index_,
                        direction == NavigateDirection_NextSibling ? 1 : -1);
        if (sibling >= 0) *element = CreateButton(state_, sibling);
        return S_OK;
      }
      default:
        return S_OK;
    }
  }
  HRESULT STDMETHODCALLTYPE GetRuntimeId(SAFEARRAY** id) override {
    const int parts[] = {UiaAppendRuntimeId, index_ + 1};
    *id = SafeArrayCreateVector(VT_I4, 0, 2);
    if (!*id) return E_OUTOFMEMORY;
    for (LONG i = 0; i < 2; i++) SafeArrayPutElement(*id, &i, (void*)&parts[i]);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE
  get_BoundingRectangle(UiaRect* bounds) override {
    *bounds = {};
    AccessibleButton button;
    if (!Current(&button)) return UIA_E_ELEMENTNOTAVAILABLE;
    const RECT rect = ScreenRect(state_->window, button.rect);
    *bounds = {static_cast<double>(rect.left), static_cast<double>(rect.top),
               static_cast<double>(rect.right - rect.left),
               static_cast<double>(rect.bottom - rect.top)};
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetEmbeddedFragmentRoots(SAFEARRAY** roots) override {
    *roots = nullptr;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE SetFocus() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE
  get_FragmentRoot(IRawElementProviderFragmentRoot** root) override {
    *root = nullptr;
    if (!state_->connected) return UIA_E_ELEMENTNOTAVAILABLE;
    return state_->root->QueryInterface(IID_PPV_ARGS(root));
  }

  // IInvokeProvider
  HRESULT STDMETHODCALLTYPE Invoke() override {
    AccessibleButton button;
    if (!Current(&button)) return UIA_E_ELEMENTNOTAVAILABLE;
    if (!button.enabled) return UIA_E_ELEMENTNOTENABLED;
    state_->invoke(index_);
    return S_OK;
  }

 private:
  bool Current(AccessibleButton* button) const {
    if (!state_->connected) return false;
    const auto buttons = state_->buttons();
    if (index_ >= static_cast<int>(buttons.size()) ||
        !Visible(buttons[index_])) {
      return false;
    }
    *button = buttons[index_];
    return true;
  }

  std::atomic<ULONG> references_{1};
  std::shared_ptr<State> state_;
  int index_;
};

IRawElementProviderFragment* CreateButton(std::shared_ptr<State> state,
                                          int index) {
  return static_cast<IRawElementProviderFragment*>(
      new Button(std::move(state), index));
}

// The window's element. The HWND host provider supplies its properties and
// the WebView; this adds the buttons as children.
class Root : public IRawElementProviderSimple,
             public IRawElementProviderFragment,
             public IRawElementProviderFragmentRoot {
 public:
  explicit Root(std::shared_ptr<State> state) : state_(std::move(state)) {}

  ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
  ULONG STDMETHODCALLTYPE Release() override {
    const ULONG references = --references_;
    if (references == 0) delete this;
    return references;
  }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override {
    if (iid == __uuidof(IUnknown) ||
        iid == __uuidof(IRawElementProviderSimple)) {
      *object = static_cast<IRawElementProviderSimple*>(this);
    } else if (iid == __uuidof(IRawElementProviderFragment)) {
      *object = static_cast<IRawElementProviderFragment*>(this);
    } else if (iid == __uuidof(IRawElementProviderFragmentRoot)) {
      *object = static_cast<IRawElementProviderFragmentRoot*>(this);
    } else {
      *object = nullptr;
      return E_NOINTERFACE;
    }
    AddRef();
    return S_OK;
  }

  // IRawElementProviderSimple
  HRESULT STDMETHODCALLTYPE
  get_ProviderOptions(ProviderOptions* options) override {
    *options = static_cast<ProviderOptions>(ProviderOptions_ServerSideProvider |
                                            ProviderOptions_UseComThreading);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetPatternProvider(PATTERNID,
                                               IUnknown** provider) override {
    *provider = nullptr;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetPropertyValue(PROPERTYID,
                                             VARIANT* value) override {
    value->vt = VT_EMPTY;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE
  get_HostRawElementProvider(IRawElementProviderSimple** provider) override {
    *provider = nullptr;
    if (!state_->connected) return UIA_E_ELEMENTNOTAVAILABLE;
    return UiaHostProviderFromHwnd(state_->window, provider);
  }

  // IRawElementProviderFragment
  HRESULT STDMETHODCALLTYPE
  Navigate(NavigateDirection direction,
           IRawElementProviderFragment** element) override {
    *element = nullptr;
    if (!state_->connected) return UIA_E_ELEMENTNOTAVAILABLE;
    if (direction != NavigateDirection_FirstChild &&
        direction != NavigateDirection_LastChild) {
      return S_OK;
    }
    const auto buttons = state_->buttons();
    const int index =
        direction == NavigateDirection_FirstChild
            ? VisibleFrom(buttons, -1, 1)
            : VisibleFrom(buttons, static_cast<int>(buttons.size()), -1);
    if (index >= 0) *element = CreateButton(state_, index);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetRuntimeId(SAFEARRAY** id) override {
    *id = nullptr;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE get_BoundingRectangle(UiaRect* bounds) override {
    *bounds = {};
    RECT rect;
    if (!state_->connected || !GetWindowRect(state_->window, &rect)) {
      return UIA_E_ELEMENTNOTAVAILABLE;
    }
    *bounds = {static_cast<double>(rect.left), static_cast<double>(rect.top),
               static_cast<double>(rect.right - rect.left),
               static_cast<double>(rect.bottom - rect.top)};
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetEmbeddedFragmentRoots(SAFEARRAY** roots) override {
    *roots = nullptr;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE SetFocus() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE
  get_FragmentRoot(IRawElementProviderFragmentRoot** root) override {
    AddRef();
    *root = this;
    return S_OK;
  }

  // IRawElementProviderFragmentRoot
  HRESULT STDMETHODCALLTYPE
  ElementProviderFromPoint(double x, double y,
                           IRawElementProviderFragment** element) override {
    *element = nullptr;
    if (!state_->connected) return UIA_E_ELEMENTNOTAVAILABLE;
    POINT point{static_cast<LONG>(x), static_cast<LONG>(y)};
    ScreenToClient(state_->window, &point);
    const auto buttons = state_->buttons();
    for (int i = 0; i < static_cast<int>(buttons.size()); i++) {
      if (PtInRect(&buttons[i].rect, point)) {
        *element = CreateButton(state_, i);
        break;
      }
    }
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE
  GetFocus(IRawElementProviderFragment** element) override {
    *element = nullptr;
    return S_OK;
  }

 private:
  std::atomic<ULONG> references_{1};
  std::shared_ptr<State> state_;
};

}  // namespace

TitleBarAccessibility::TitleBarAccessibility(
    HWND window, std::function<std::vector<AccessibleButton>()> buttons,
    std::function<void(int)> invoke)
    : state_(std::make_shared<State>()) {
  state_->window = window;
  state_->buttons = std::move(buttons);
  state_->invoke = std::move(invoke);
  state_->root = static_cast<IRawElementProviderSimple*>(new Root(state_));
  reported_ = state_->buttons();
}

TitleBarAccessibility::~TitleBarAccessibility() {
  state_->connected = false;
  UiaDisconnectProvider(state_->root);
  // The root holds the state, so break the cycle here.
  IRawElementProviderSimple* root = state_->root;
  state_->root = nullptr;
  root->Release();
}

namespace {

void RaiseChange(IRawElementProviderSimple* provider, PROPERTYID property,
                 VARIANT old_value, VARIANT new_value) {
  UiaRaiseAutomationPropertyChangedEvent(provider, property, old_value,
                                         new_value);
  VariantClear(&old_value);
  VariantClear(&new_value);
}

VARIANT StringVariant(const std::wstring& value) {
  VARIANT variant;
  variant.vt = VT_BSTR;
  variant.bstrVal = SysAllocString(value.c_str());
  return variant;
}

VARIANT BoolVariant(bool value) {
  VARIANT variant;
  variant.vt = VT_BOOL;
  variant.boolVal = value ? VARIANT_TRUE : VARIANT_FALSE;
  return variant;
}

}  // namespace

void TitleBarAccessibility::Update() {
  auto buttons = state_->buttons();
  const auto previous = std::exchange(reported_, buttons);
  if (!UiaClientsAreListening()) return;
  bool structure = previous.size() != buttons.size();
  for (size_t i = 0; i < buttons.size() && i < previous.size(); i++) {
    if (Visible(previous[i]) != Visible(buttons[i])) structure = true;
    if (!Visible(buttons[i])) continue;
    const bool renamed = previous[i].name != buttons[i].name;
    const bool toggled = previous[i].enabled != buttons[i].enabled;
    if (!renamed && !toggled) continue;
    IRawElementProviderSimple* button = static_cast<IRawElementProviderSimple*>(
        new Button(state_, static_cast<int>(i)));
    if (renamed) {
      RaiseChange(button, UIA_NamePropertyId, StringVariant(previous[i].name),
                  StringVariant(buttons[i].name));
    }
    if (toggled) {
      RaiseChange(button, UIA_IsEnabledPropertyId,
                  BoolVariant(previous[i].enabled),
                  BoolVariant(buttons[i].enabled));
    }
    button->Release();
  }
  if (structure) {
    UiaRaiseStructureChangedEvent(state_->root,
                                  StructureChangeType_ChildrenInvalidated,
                                  nullptr, 0);
  }
}

bool TitleBarAccessibility::HandleGetObject(WPARAM wparam, LPARAM lparam,
                                            LRESULT* result) {
  if (static_cast<long>(lparam) != static_cast<long>(UiaRootObjectId)) {
    return false;
  }
  *result =
      UiaReturnRawElementProvider(state_->window, wparam, lparam, state_->root);
  return true;
}

}  // namespace dww
