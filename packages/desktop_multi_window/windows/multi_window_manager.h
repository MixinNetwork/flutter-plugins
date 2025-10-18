#ifndef DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_MANAGER_H_
#define DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_MANAGER_H_

#include <cstdint>
#include <map>
#include <string>

#include "base_flutter_window.h"
#include "flutter_plugin_registrar.h"
#include "flutter_window.h"

class MultiWindowManager
    : public std::enable_shared_from_this<MultiWindowManager>,
      public FlutterWindowCallback {
 public:
  static MultiWindowManager* Instance();

  MultiWindowManager();

  std::string Create(const flutter::EncodableMap* args);

  void AttachFlutterMainWindow(HWND main_window_handle,
                               FlutterDesktopPluginRegistrarRef registrar);

  BaseFlutterWindow* GetWindow(const std::string& window_id);

  void OnWindowClose(const std::string& id) override;

  void OnWindowDestroy(const std::string& id) override;

 private:
  std::map<std::string, std::unique_ptr<BaseFlutterWindow>> windows_;
};

#endif  // DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_MANAGER_H_
