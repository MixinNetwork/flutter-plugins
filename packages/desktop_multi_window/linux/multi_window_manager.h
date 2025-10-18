#ifndef DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_MANAGER_H_
#define DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_MANAGER_H_

#include <cstdint>
#include <string>
#include <map>
#include <cmath>

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include "base_flutter_window.h"
#include "flutter_window.h"

class MultiWindowManager : public std::enable_shared_from_this<MultiWindowManager>, public FlutterWindowCallback {

 public:
  static MultiWindowManager *Instance();

  MultiWindowManager();

  virtual ~MultiWindowManager();

  std::string Create(const std::string &args);

  void AttachMainWindow(GtkWidget *main_flutter_window, FlPluginRegistrar *registrar);

  BaseFlutterWindow* GetWindow(const std::string& window_id);

  void OnWindowClose(const std::string& id) override;

  void OnWindowDestroy(const std::string& id) override;

 private:

  std::map<std::string, std::unique_ptr<BaseFlutterWindow>> windows_;

};

#endif //DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_MANAGER_H_
