#ifndef DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_MANAGER_H_
#define DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_MANAGER_H_

#include <cmath>
#include <cstdint>
#include <map>
#include <string>
#include <vector>

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include "flutter_window.h"

class MultiWindowManager
    : public std::enable_shared_from_this<MultiWindowManager> {
 public:
  static MultiWindowManager* Instance();

  MultiWindowManager();

  virtual ~MultiWindowManager();

  std::string Create(FlValue* args);

  void AttachMainWindow(GtkWidget* main_flutter_window,
                        FlPluginRegistrar* registrar);

  FlutterWindow* GetWindow(const std::string& window_id);

  FlValue* GetAllWindows();

  std::vector<std::string> GetAllWindowIds();

  void RemoveWindow(const std::string& window_id);

 private:

  void ObserveWindowClose(const std::string& window_id,
                            GtkWindow* window);

  void NotifyWindowsChanged();

  std::map<std::string, std::unique_ptr<FlutterWindow>> windows_;
};

#endif  // DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_MANAGER_H_
