//
// Created by boyan on 11/23/21.
//


#include "message_channel_plugin.h"

#include <set>
#include <vector>

#include "glib.h"

namespace {

class ClientMessageChannelPlugin {

 public:
  explicit ClientMessageChannelPlugin(FlMethodChannel *channel);

  FlMethodChannel *RefChannel() const {
    return FL_METHOD_CHANNEL(g_object_ref(channel_));
  }

  ~ClientMessageChannelPlugin();

 private:
  FlMethodChannel *channel_;
};

class ServerMessageChannelPlugin {

 public:

  void AddClient(ClientMessageChannelPlugin *client) {
    clients_.insert(client);
  }

  void RemoveClient(ClientMessageChannelPlugin *client) {
    clients_.erase(client);
  }

  void DispatchMethodCall(FlMethodCall *call, ClientMessageChannelPlugin *client_from) {
    // Sending may re-enter GTK and remove another client. Snapshot owned
    // channel references rather than iterating raw client pointers while sending.
    std::vector<FlMethodChannel *> channels;
    for (auto *client : clients_) {
      if (client != client_from) channels.push_back(client->RefChannel());
    }
    for (auto *channel : channels) {
      fl_method_channel_invoke_method(channel, fl_method_call_get_name(call),
                                      fl_method_call_get_args(call), nullptr,
                                      nullptr, nullptr);
      g_object_unref(channel);
    }
  }

 private:
  std::set<ClientMessageChannelPlugin *> clients_;

};

ServerMessageChannelPlugin *g_server_message_channel_plugin = nullptr;

ClientMessageChannelPlugin::ClientMessageChannelPlugin(FlMethodChannel *channel) : channel_(channel) {
  g_object_ref(channel_);
  g_server_message_channel_plugin->AddClient(this);
}

ClientMessageChannelPlugin::~ClientMessageChannelPlugin() {
  g_server_message_channel_plugin->RemoveClient(this);
  g_object_unref(channel_);
}

void client_plugin_proxy_dispatch_method_call(FlMethodChannel *channel, FlMethodCall *call, gpointer user_data) {
  auto *client = static_cast<ClientMessageChannelPlugin *>(user_data);
  g_assert(g_server_message_channel_plugin);
  g_server_message_channel_plugin->DispatchMethodCall(call, client);
  fl_method_call_respond_success(call, nullptr, nullptr);
}

}

void client_message_channel_plugin_register_with_registrar(FlPluginRegistrar *registrar) {
  // A shared engine has many FlViews, but exactly one message client. Key
  // registration to its messenger rather than to a view or registrar.
  FlBinaryMessenger *messenger = fl_plugin_registrar_get_messenger(registrar);
  const char *registration_key = "desktop-webview-window-message-client";
  if (g_object_get_data(G_OBJECT(messenger), registration_key) != nullptr) return;
  g_object_set_data(G_OBJECT(messenger), registration_key, GINT_TO_POINTER(1));

  static ServerMessageChannelPlugin server;
  g_server_message_channel_plugin = &server;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(messenger,
                                                   "webview_message/client_channel",
                                                   FL_METHOD_CODEC(codec));
  auto *client_message_channel_plugin = new ClientMessageChannelPlugin(channel);
  fl_method_channel_set_method_call_handler(channel,
                                            client_plugin_proxy_dispatch_method_call,
                                            client_message_channel_plugin,
                                            [](gpointer pointer) {
                                              delete static_cast<ClientMessageChannelPlugin *>(pointer);
                                            });
}
