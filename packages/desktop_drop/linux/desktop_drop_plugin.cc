#include "include/desktop_drop/desktop_drop_plugin.h"
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <algorithm>
#include <memory>
#include <set>
#include <string>
#include <vector>

namespace {
constexpr char kPortal[] = "application/vnd.portal.filetransfer";
constexpr char kUris[] = "text/uri-list";
constexpr char kUtf8[] = "UTF8_STRING";
constexpr char kPlain[] = "text/plain;charset=utf-8";
constexpr char kString[] = "STRING";
struct State;
struct File { std::string path; std::string name; };
struct Drag {
  explicit Drag(GdkDragContext* value, int64_t number)
      : context(GDK_DRAG_CONTEXT(g_object_ref(value))), session(number) {}
  ~Drag() { g_object_unref(context); if (portal_cancel) g_object_unref(portal_cancel); }
  GdkDragContext* context;
  int64_t session;
  int64_t revision = 0;
  gint x = 0, y = 0;
  guint time = 0;
  bool dropping = false, finished = false, query_pending = false;
  bool inside = true, data_requested = false;
  bool loading = false, portal_started = false, portal_resolved = false;
  bool has_file = false, has_url = false, has_text = false;
  std::set<GdkAtom> pending;
  std::vector<File> files;
  std::vector<std::string> urls;
  std::string text, uris, key;
  GCancellable* portal_cancel = nullptr;
};
struct State : std::enable_shared_from_this<State> {
  GtkWidget* view = nullptr;  // Weak: the view owns the plugin.
  FlMethodChannel* channel = nullptr;
  int64_t view_id = 0, generation = 0, next_session = 0, next_request = 0;
  bool closed = false;
  std::shared_ptr<Drag> drag;
  ~State() { if (channel) g_object_unref(channel); }
  void Close() {
    if (closed) return;
    closed = true;
    fl_method_channel_set_method_call_handler(channel, nullptr, nullptr, nullptr);
    if (drag && !drag->finished && drag->dropping) {
      gtk_drag_finish(drag->context, FALSE, FALSE, drag->time);
      drag->finished = true;
    }
    if (drag && drag->portal_cancel) g_cancellable_cancel(drag->portal_cancel);
    view = nullptr;
  }
};
struct Query {
  std::shared_ptr<State> state;
  std::shared_ptr<Drag> drag;
  int64_t revision, request;
  bool final;
  bool finished = false;
  guint timer = 0;
  GCancellable* cancel = g_cancellable_new();
  ~Query() { g_object_unref(cancel); }
};
using QueryRef = std::shared_ptr<Query>;
using DragRef = std::shared_ptr<Drag>;
using StateRef = std::shared_ptr<State>;

void Set(FlValue* map, const char* key, FlValue* value) {
  fl_value_set_string_take(map, key, value);
}
void Invoke(const StateRef& state, const char* method, FlValue* args) {
  if (!state->closed) fl_method_channel_invoke_method(state->channel, method, args, nullptr, nullptr, nullptr);
}
bool Current(const StateRef& state, const DragRef& drag) {
  return !state->closed && state->view && state->drag == drag && !drag->finished;
}

FlValue* Offer(const DragRef& drag) {
  FlValue* result = fl_value_new_map();
  g_autoptr(FlValue) types = fl_value_new_list();
  g_autoptr(FlValue) files = fl_value_new_list();
  g_autoptr(FlValue) urls = fl_value_new_list();
  if (drag->has_file) fl_value_append_take(types, fl_value_new_string("file"));
  if (drag->has_url) fl_value_append_take(types, fl_value_new_string("url"));
  if (drag->has_text) fl_value_append_take(types, fl_value_new_string("text"));
  for (const auto& file : drag->files) {
    FlValue* entry = fl_value_new_map();
    Set(entry, "path", fl_value_new_string(file.path.c_str()));
    Set(entry, "name", fl_value_new_string(file.name.c_str()));
    if (drag->dropping) Set(entry, "isDirectory", fl_value_new_bool(g_file_test(file.path.c_str(), G_FILE_TEST_IS_DIR)));
    fl_value_append_take(files, entry);
  }
  for (const auto& url : drag->urls) fl_value_append_take(urls, fl_value_new_string(url.c_str()));
  Set(result, "types", fl_value_ref(types));
  Set(result, "files", fl_value_ref(files));
  Set(result, "urls", fl_value_ref(urls));
  Set(result, "text", drag->has_text && !drag->loading ? fl_value_new_string(drag->text.c_str()) : fl_value_new_null());
  Set(result, "isComplete", fl_value_new_bool(!drag->loading && (drag->key.empty() || drag->portal_resolved)));
  const auto& raw = drag->key.empty() ? drag->uris : drag->key;
  Set(result, "rawText", raw.empty() ? fl_value_new_null() : fl_value_new_string(raw.c_str()));
  return result;
}
FlValue* Arguments(const StateRef& state, const DragRef& drag, int64_t request, int phase, int64_t target) {
  FlValue* result = fl_value_new_map();
  Set(result, "view", fl_value_new_int(state->view_id));
  Set(result, "generation", fl_value_new_int(state->generation));
  Set(result, "session", fl_value_new_int(drag->session));
  Set(result, "request", fl_value_new_int(request));
  Set(result, "phase", fl_value_new_int(phase));
  Set(result, "target", fl_value_new_int(target));
  Set(result, "x", fl_value_new_float(drag->x));
  Set(result, "y", fl_value_new_float(drag->y));
  Set(result, "offer", Offer(drag));
  return result;
}

void RequestQuery(const StateRef& state, const DragRef& drag);
void ResolvePortal(const StateRef& state, const DragRef& drag);

void Apply(const QueryRef& query, int64_t target) {
  auto state = query->state;
  auto drag = query->drag;
  drag->query_pending = false;
  if (!Current(state, drag) || (!drag->inside && !drag->dropping)) return;
  if (query->revision != drag->revision) {
    if (drag->dropping && !drag->key.empty() && !drag->portal_resolved) ResolvePortal(state, drag);
    else RequestQuery(state, drag);
    return;
  }
  if (!(gdk_drag_context_get_actions(drag->context) & GDK_ACTION_COPY)) target = 0;
  g_autoptr(FlValue) args = Arguments(state, drag, query->request, query->final ? 2 : 1, target);
  Invoke(state, "feedback", args);
  if (query->final) {
    if (target > 0) Invoke(state, "drop", args);
    gtk_drag_finish(drag->context, target > 0, FALSE, drag->time);
    drag->finished = true;
  } else {
    gdk_drag_status(drag->context, target > 0 ? GDK_ACTION_COPY : static_cast<GdkDragAction>(0), drag->time);
  }
}

void QueryReceived(GObject* source, GAsyncResult* result, gpointer user_data) {
  std::unique_ptr<QueryRef> reference(static_cast<QueryRef*>(user_data));
  const auto query = *reference;
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) response = fl_method_channel_invoke_method_finish(FL_METHOD_CHANNEL(source), result, &error);
  if (query->finished) return;
  query->finished = true;
  if (query->timer) { g_source_remove(query->timer); query->timer = 0; }
  FlValue* value = response ? fl_method_response_get_result(response, &error) : nullptr;
  const int64_t target = value && fl_value_get_type(value) == FL_VALUE_TYPE_INT ? fl_value_get_int(value) : 0;
  Apply(query, target);
}

void RequestQuery(const StateRef& state, const DragRef& drag) {
  if (!Current(state, drag) || drag->query_pending || (!drag->inside && !drag->dropping)) return;
  if (drag->dropping && drag->loading) return;
  if (drag->dropping && !drag->key.empty() && !drag->portal_resolved) { ResolvePortal(state, drag); return; }
  drag->query_pending = true;
  auto query = std::make_shared<Query>();
  query->state = state; query->drag = drag; query->revision = drag->revision;
  query->request = ++state->next_request; query->final = drag->dropping;
  query->timer = g_timeout_add_full(G_PRIORITY_DEFAULT, 100, [](gpointer data) -> gboolean {
    const auto request = *static_cast<QueryRef*>(data);
    request->timer = 0;
    if (!request->finished) {
      request->finished = true;
      g_cancellable_cancel(request->cancel);
      Apply(request, 0);
    }
    return G_SOURCE_REMOVE;
  }, new QueryRef(query), [](gpointer data) { delete static_cast<QueryRef*>(data); });
  g_autoptr(FlValue) args = Arguments(state, drag, query->request, query->final ? 2 : 1, 0);
  fl_method_channel_invoke_method(state->channel, "query", args, query->cancel, QueryReceived, new QueryRef(query));
}

void AddPath(const DragRef& drag, const char* path) {
  if (!path || !*path) return;
  if (std::any_of(drag->files.begin(), drag->files.end(), [path](const File& file) { return file.path == path; })) return;
  g_autofree gchar* name = g_path_get_basename(path);
  drag->files.push_back({path, name});
}
void ReadUris(const DragRef& drag, const std::string& text) {
  drag->uris = text;
  g_auto(GStrv) uris = g_uri_list_extract_uris(text.c_str());
  for (gchar** uri = uris; uri && *uri; ++uri) {
    g_autofree gchar* path = g_filename_from_uri(*uri, nullptr, nullptr);
    if (path) AddPath(drag, path);
    else {
      g_autofree gchar* scheme = g_uri_parse_scheme(*uri);
      if (scheme) {
        drag->urls.emplace_back(*uri);
        if (strcmp(scheme, "http") && strcmp(scheme, "https")) AddPath(drag, *uri);
      }
    }
  }
  if (!drag->files.empty()) drag->has_file = true;
  if (!drag->urls.empty()) drag->has_url = true;
}

struct PortalRequest { StateRef state; DragRef drag; };
void PortalFinished(PortalRequest* request, gchar** paths) {
  const auto state = request->state; const auto drag = request->drag;
  if (!Current(state, drag)) return;
  if (paths && *paths) {
    drag->files.clear();
    for (gchar** path = paths; *path; ++path) AddPath(drag, *path);
  }
  drag->portal_resolved = true;
  drag->has_file = !drag->files.empty();
  ++drag->revision;
  RequestQuery(state, drag);
}
void PortalReply(GObject* source, GAsyncResult* result, gpointer user_data) {
  std::unique_ptr<PortalRequest> request(static_cast<PortalRequest*>(user_data));
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), result, &error);
  g_auto(GStrv) paths = nullptr;
  if (reply) g_variant_get(reply, "(^as)", &paths);
  PortalFinished(request.get(), paths);
}
void PortalBus(GObject*, GAsyncResult* result, gpointer user_data) {
  std::unique_ptr<PortalRequest> request(static_cast<PortalRequest*>(user_data));
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) bus = g_bus_get_finish(result, &error);
  if (!bus || !Current(request->state, request->drag)) { PortalFinished(request.get(), nullptr); return; }
  auto drag = request->drag;
  g_dbus_connection_call(bus, "org.freedesktop.portal.Documents", "/org/freedesktop/portal/documents",
      "org.freedesktop.portal.FileTransfer", "RetrieveFiles",
      g_variant_new("(s@a{sv})", drag->key.c_str(), g_variant_new_array(G_VARIANT_TYPE("{sv}"), nullptr, 0)),
      G_VARIANT_TYPE("(as)"), G_DBUS_CALL_FLAGS_NONE, 5000, drag->portal_cancel,
      PortalReply, request.release());
}
void ResolvePortal(const StateRef& state, const DragRef& drag) {
  if (drag->portal_started || !Current(state, drag)) return;
  drag->portal_started = true;
  drag->portal_cancel = g_cancellable_new();
  g_bus_get(G_BUS_TYPE_SESSION, drag->portal_cancel, PortalBus, new PortalRequest{state, drag});
}

DragRef GetDrag(const StateRef& state, GdkDragContext* context) {
  if (state->drag && state->drag->context == context && !state->drag->finished) return state->drag;
  auto drag = std::make_shared<Drag>(context, ++state->next_session);
  const GList* targets = gdk_drag_context_list_targets(context);
  drag->has_file = g_list_find(const_cast<GList*>(targets), gdk_atom_intern_static_string(kPortal)) ||
                   g_list_find(const_cast<GList*>(targets), gdk_atom_intern_static_string(kUris));
  drag->has_url = g_list_find(const_cast<GList*>(targets), gdk_atom_intern_static_string(kUris)) != nullptr;
  drag->has_text = g_list_find(const_cast<GList*>(targets), gdk_atom_intern_static_string(kUtf8)) ||
                   g_list_find(const_cast<GList*>(targets), gdk_atom_intern_static_string(kPlain)) ||
                   g_list_find(const_cast<GList*>(targets), gdk_atom_intern_static_string(kString)) ||
                   g_list_find(const_cast<GList*>(targets), gdk_atom_intern_static_string("text/plain"));
  state->drag = drag;
  return drag;
}
void Load(const StateRef& state, const DragRef& drag) {
  if (drag->data_requested) return;
  drag->data_requested = true;
  const GList* targets = gdk_drag_context_list_targets(drag->context);
  for (const char* type : {kPortal, kUris}) {
    const GdkAtom atom = gdk_atom_intern_static_string(type);
    if (g_list_find(const_cast<GList*>(targets), atom)) drag->pending.insert(atom);
  }
  for (const char* type : {kPlain, kUtf8, "text/plain", kString}) {
    const GdkAtom atom = gdk_atom_intern(type, FALSE);
    if (g_list_find(const_cast<GList*>(targets), atom)) { drag->pending.insert(atom); break; }
  }
  drag->loading = !drag->pending.empty();
  // Insert all atoms before requesting: a local selection can answer reentrantly.
  const auto pending = drag->pending;
  for (GdkAtom atom : pending) gtk_drag_get_data(state->view, drag->context, atom, drag->time);
}
}  // namespace

#define DESKTOP_DROP_PLUGIN(obj) (G_TYPE_CHECK_INSTANCE_CAST((obj), desktop_drop_plugin_get_type(), DesktopDropPlugin))
struct _DesktopDropPlugin { GObject parent_instance; StateRef* state; };
G_DEFINE_TYPE(DesktopDropPlugin, desktop_drop_plugin, g_object_get_type())

static StateRef GetState(gpointer data) { return *DESKTOP_DROP_PLUGIN(data)->state; }
static gboolean Motion(GtkWidget*, GdkDragContext* context, gint x, gint y, guint time, gpointer data) {
  const auto state = GetState(data); const auto drag = GetDrag(state, context);
  drag->inside = true; drag->x = x; drag->y = y; drag->time = time; ++drag->revision;
  Load(state, drag); RequestQuery(state, drag);
  return TRUE;
}
static gboolean Drop(GtkWidget*, GdkDragContext* context, gint x, gint y, guint time, gpointer data) {
  const auto state = GetState(data); const auto drag = GetDrag(state, context);
  drag->inside = true; drag->x = x; drag->y = y; drag->time = time; drag->dropping = true; ++drag->revision;
  Load(state, drag); RequestQuery(state, drag);
  return TRUE;
}
static void Leave(GtkWidget*, GdkDragContext* context, guint, gpointer data) {
  const auto state = GetState(data);
  if (!state->drag || state->drag->context != context || state->drag->dropping) return;
  state->drag->inside = false;
  ++state->drag->revision;
  g_autoptr(FlValue) args = Arguments(state, state->drag, ++state->next_request, 3, 0);
  Invoke(state, "exit", args);
}
static void DataReceived(GtkWidget*, GdkDragContext* context, gint, gint, GtkSelectionData* selection,
                         guint, guint, gpointer data) {
  const auto state = GetState(data);
  const auto drag = state->drag;
  if (!drag || drag->context != context || !Current(state, drag)) return;
  const GdkAtom target = gtk_selection_data_get_target(selection);
  if (!drag->pending.erase(target)) return;
  const gint length = gtk_selection_data_get_length(selection);
  const auto* bytes = gtk_selection_data_get_data(selection);
  if (length > 0 && bytes) {
    std::string text(reinterpret_cast<const char*>(bytes), length);
    while (!text.empty() && text.back() == '\0') text.pop_back();
    if (!g_utf8_validate(text.c_str(), text.size(), nullptr)) text.clear();
    if (target == gdk_atom_intern_static_string(kPortal)) drag->key = text;
    else if (target == gdk_atom_intern_static_string(kUris)) ReadUris(drag, text);
    else { drag->text = text; drag->has_text = true; }
  }
  if (drag->pending.empty()) {
    drag->loading = false;
    drag->has_file = !drag->files.empty() || !drag->key.empty();
    drag->has_url = !drag->urls.empty();
    ++drag->revision;
    RequestQuery(state, drag);
  }
}
static void MethodCall(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  const auto state = GetState(data);
  if (strcmp(fl_method_call_get_name(call), "initialize") == 0) {
    auto* args = fl_method_call_get_args(call);
    FlValue* id = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(args, "view") : nullptr;
    if (!id || fl_value_get_type(id) != FL_VALUE_TYPE_INT || fl_value_get_int(id) != state->view_id) {
      fl_method_call_respond_error(call, "unsupported_view", "Flutter view is not attached", nullptr, nullptr); return;
    }
    if (state->drag) {
      if (!state->drag->finished && state->drag->dropping) gtk_drag_finish(state->drag->context, FALSE, FALSE, state->drag->time);
      state->drag->finished = true;
      if (state->drag->portal_cancel) g_cancellable_cancel(state->drag->portal_cancel);
      state->drag.reset();
    }
    ++state->generation;
    g_autoptr(FlValue) result = fl_value_new_map(); Set(result, "view", fl_value_new_int(state->view_id));
    Set(result, "generation", fl_value_new_int(state->generation));
    fl_method_call_respond_success(call, result, nullptr);
  } else fl_method_call_respond_not_implemented(call, nullptr);
}
static void desktop_drop_plugin_dispose(GObject* object) {
  auto* plugin = DESKTOP_DROP_PLUGIN(object);
  if (plugin->state) (*plugin->state)->Close();
  G_OBJECT_CLASS(desktop_drop_plugin_parent_class)->dispose(object);
}
static void desktop_drop_plugin_finalize(GObject* object) {
  delete DESKTOP_DROP_PLUGIN(object)->state;
  G_OBJECT_CLASS(desktop_drop_plugin_parent_class)->finalize(object);
}
static void desktop_drop_plugin_class_init(DesktopDropPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = desktop_drop_plugin_dispose;
  G_OBJECT_CLASS(klass)->finalize = desktop_drop_plugin_finalize;
}
static void desktop_drop_plugin_init(DesktopDropPlugin* self) { self->state = new StateRef(std::make_shared<State>()); }
void desktop_drop_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  auto* plugin = DESKTOP_DROP_PLUGIN(g_object_new(desktop_drop_plugin_get_type(), nullptr));
  const auto state = GetState(plugin);
  FlView* view = fl_plugin_registrar_get_view(registrar);
  if (!view) { g_object_unref(plugin); return; }
  state->view = GTK_WIDGET(view); state->view_id = fl_view_get_id(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  state->channel = fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar), "desktop_drop", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(state->channel, MethodCall, plugin, nullptr);
  GtkTargetEntry targets[] = {{const_cast<char*>(kPortal), 0, 0}, {const_cast<char*>(kUris), 0, 1},
    {const_cast<char*>(kPlain), 0, 2}, {const_cast<char*>(kUtf8), 0, 3},
    {const_cast<char*>("text/plain"), 0, 4}, {const_cast<char*>(kString), 0, 5}};
  gtk_drag_dest_set(GTK_WIDGET(view), static_cast<GtkDestDefaults>(0), targets, G_N_ELEMENTS(targets), GDK_ACTION_COPY);
  gtk_drag_dest_set_track_motion(GTK_WIDGET(view), TRUE);
  g_signal_connect_object(view, "drag-motion", G_CALLBACK(Motion), plugin, static_cast<GConnectFlags>(0));
  g_signal_connect_object(view, "drag-drop", G_CALLBACK(Drop), plugin, static_cast<GConnectFlags>(0));
  g_signal_connect_object(view, "drag-leave", G_CALLBACK(Leave), plugin, static_cast<GConnectFlags>(0));
  g_signal_connect_object(view, "drag-data-received", G_CALLBACK(DataReceived), plugin, static_cast<GConnectFlags>(0));
  g_signal_connect_object(fl_view_get_engine(view), "pre-engine-restart", G_CALLBACK(+[](FlEngine*, gpointer data) {
    const auto state = GetState(data);
    if (!state->drag) return;
    const auto drag = state->drag;
    if (!drag->finished && drag->dropping) gtk_drag_finish(drag->context, FALSE, FALSE, drag->time);
    drag->finished = true;
    if (drag->portal_cancel) g_cancellable_cancel(drag->portal_cancel);
    state->drag.reset();
  }), plugin, static_cast<GConnectFlags>(0));
  g_object_set_data_full(G_OBJECT(view), "desktop_drop_plugin", plugin, g_object_unref);
}
