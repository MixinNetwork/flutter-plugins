//
// Created by yangbin on 2022/1/11.
//

#ifndef DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_MANAGER_H_
#define DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_MANAGER_H_

#include <cstdint>
#include <string>
#include <map>

#include "flutter_window.h"

class MultiWindowManager : public std::enable_shared_from_this<MultiWindowManager>, public FlutterWindowCallback {

 public:
  static MultiWindowManager *Instance();

  MultiWindowManager();

  int64_t Create(std::string args);

  void Show(int64_t id);

  void Hide(int64_t id);

  void Close(int64_t id);

  void SetFrame(int64_t id, double_t x, double_t y, double_t width, double_t height);

  void Center(int64_t id);

  void SetTitle(int64_t id, const std::string &title);

  void OnWindowClose(int64_t id) override;

  void OnWindowDestroy(int64_t id) override;

 private:

  std::map<int64_t, std::unique_ptr<FlutterWindow>> windows_;

};

#endif //DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_MANAGER_H_
