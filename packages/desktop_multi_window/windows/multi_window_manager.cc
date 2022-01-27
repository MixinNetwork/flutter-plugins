//
// Created by yangbin on 2022/1/11.
//

#include "multi_window_manager.h"

namespace {
int64_t g_next_id_ = 0;
}

// static
MultiWindowManager *MultiWindowManager::Instance() {
  static auto manager = std::make_shared<MultiWindowManager>();
  return manager.get();
}

MultiWindowManager::MultiWindowManager() : windows_() {

}

int64_t MultiWindowManager::Create(std::string args) {
  g_next_id_++;
  int64_t id = g_next_id_;
  auto window = std::make_unique<FlutterWindow>(id, std::move(args), shared_from_this());
  windows_[id] = std::move(window);
  return id;
}

void MultiWindowManager::Show(int64_t id) {
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->Show();
  }
}

void MultiWindowManager::Hide(int64_t id) {
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->Hide();
  }
}

void MultiWindowManager::Close(int64_t id) {
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->Close();
  }
}

void MultiWindowManager::SetFrame(int64_t id, double x, double y, double width, double height) {
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->SetBounds(x, y, width, height);
  }
}

void MultiWindowManager::SetTitle(int64_t id, const std::string& title) {
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->SetTitle(title);
  }
}

void MultiWindowManager::Center(int64_t id) {
  auto window = windows_.find(id);
  if (window != windows_.end()) {
    window->second->Center();
  }
}

void MultiWindowManager::OnWindowClose(int64_t id) {
}

void MultiWindowManager::OnWindowDestroy(int64_t id) {
  windows_.erase(id);
}

