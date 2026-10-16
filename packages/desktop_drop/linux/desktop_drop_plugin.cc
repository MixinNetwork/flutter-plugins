#include "include/desktop_drop/desktop_drop_plugin.h"
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include "ffi_transport.h"

#include <algorithm>
#include <memory>
#include <map>
#include <set>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace {
constexpr char kPortal[] = "application/vnd.portal.filetransfer";
constexpr char kUris[] = "text/uri-list";
constexpr char kUtf8[] = "UTF8_STRING";
constexpr char kPlain[] = "text/plain;charset=utf-8";
constexpr char kString[] = "STRING";
struct State;
struct Reader { std::shared_ptr<std::vector<uint8_t>> bytes; size_t offset; };
struct Open { FfiCallRef call; size_t start; };
struct File { std::string path; std::string name; };
struct Drag {
  explicit Drag(GdkDragContext* value, int64_t number)
      : context(GDK_DRAG_CONTEXT(g_object_ref(value))), session(number) {}
  ~Drag() { Finish(false); if (offer) fl_value_unref(offer); g_object_unref(context); if (portal_cancel) g_object_unref(portal_cancel); }
  GdkDragContext* context;
  int64_t session;
  int64_t revision = 0;
  int32_t operation = 0;
  gint x = 0, y = 0;
  guint time = 0;
  bool dropping = false, delivered = false, finished = false, query_pending = false;
  bool inside = true, data_requested = false;
  bool loading = false, portal_started = false, portal_resolved = false;
  bool has_file = false;
  FlValue* offer = nullptr;
  bool offer_sent = false;
  std::set<GdkAtom> pending;
  std::vector<File> files;
  std::string key;
  std::map<std::string, std::optional<std::string>> strings;
  std::map<GdkAtom, std::string> string_types;
  std::string binary_type, binary_name, binary_mime;
  std::shared_ptr<std::vector<uint8_t>> binary_data;
  std::map<int64_t, Reader> readers;
  std::vector<Open> pending_reads;
  guint read_timer = 0;
  void ReleaseReaders() {
    if (read_timer) { g_source_remove(read_timer); read_timer = 0; }
    readers.clear();
    for (const auto& pending : pending_reads) {
      pending.call->Error("source_expired", "Dropped source is no longer available");
    }
    pending_reads.clear();
  }
  GCancellable* portal_cancel = nullptr;
  void Finish(bool success) {
    if (finished) return;
    finished = true;
    ReleaseReaders();
    binary_data.reset();
    if (portal_cancel) g_cancellable_cancel(portal_cancel);
    // Hover cleanup must not report a drop completion to GTK.
    if (dropping) gtk_drag_finish(context, success, success && operation == 2, time);
  }
};
struct State : std::enable_shared_from_this<State> {
  GtkWidget* view = nullptr;  // Weak: the view owns the plugin.
  std::unique_ptr<FfiTransport> transport;
  int64_t view_id = 0, generation = 0, next_session = 0, next_request = 0;
  bool closed = false;
  std::shared_ptr<Drag> drag;
  std::map<int64_t, std::shared_ptr<Drag>> sources;
  int64_t next_reader = 0;
  void ResetSources() {
    const auto current = std::move(drag);
    const auto active_sources = std::move(sources);
    sources.clear();
    if (current) current->Finish(false);
    for (const auto& entry : active_sources) entry.second->Finish(false);
  }
  void Close() {
    if (closed) return;
    closed = true;
    ResetSources();
    transport.reset();
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
  int64_t rpc_request = 0;
  FlValue* offer_snapshot = nullptr;
  ~Query() { if (offer_snapshot) fl_value_unref(offer_snapshot); }
};
using QueryRef = std::shared_ptr<Query>;
using DragRef = std::shared_ptr<Drag>;
using StateRef = std::shared_ptr<State>;

void Set(FlValue* map, const char* key, FlValue* value) {
  fl_value_set_string_take(map, key, value);
}
void Invoke(const StateRef& state, const char* method, FlValue* args) {
  if (!state->closed) state->transport->Invoke(method, args);
}
bool Current(const StateRef& state, const DragRef& drag) {
  return !state->closed && state->view && state->drag == drag && !drag->finished && !drag->delivered;
}

void InvalidateOffer(const DragRef& drag) {
  if (drag->offer) fl_value_unref(drag->offer);
  drag->offer = nullptr;
  drag->offer_sent = false;
}
FlValue* Offer(const DragRef& drag) {
  if (drag->offer) return fl_value_ref(drag->offer);
  FlValue* result = fl_value_new_map();
  g_autoptr(FlValue) files = fl_value_new_list();
  g_autoptr(FlValue) strings = fl_value_new_list();
  g_autoptr(FlValue) operations = fl_value_new_list();
  const auto actions = gdk_drag_context_get_actions(drag->context);
  if (actions & GDK_ACTION_COPY) fl_value_append_take(operations, fl_value_new_string("copy"));
  if (actions & GDK_ACTION_MOVE) fl_value_append_take(operations, fl_value_new_string("move"));
  if (actions & GDK_ACTION_LINK) fl_value_append_take(operations, fl_value_new_string("link"));
  for (const auto& file : drag->files) {
    FlValue* entry = fl_value_new_map();
    Set(entry, "path", fl_value_new_string(file.path.c_str()));
    Set(entry, "name", fl_value_new_string(file.name.c_str()));
    Set(entry, "isDirectory", fl_value_new_bool(g_file_test(file.path.c_str(), G_FILE_TEST_IS_DIR)));
    fl_value_append_take(files, entry);
  }
  if (!drag->binary_type.empty() && drag->files.empty()) {
    FlValue* entry = fl_value_new_map();
    Set(entry, "name", fl_value_new_string(drag->binary_name.c_str()));
    Set(entry, "mimeType", fl_value_new_string(drag->binary_mime.c_str()));
    Set(entry, "source", fl_value_new_int(0));
    fl_value_append_take(files, entry);
  } else if (drag->has_file && drag->files.empty()) {
    FlValue* entry = fl_value_new_map();
    Set(entry, "name", fl_value_new_string(""));
    fl_value_append_take(files, entry);
  }
  for (const auto& string : drag->strings) {
    FlValue* entry = fl_value_new_map();
    Set(entry, "mimeType", fl_value_new_string(string.first.c_str()));
    Set(entry, "value", string.second ? fl_value_new_string(string.second->c_str()) : fl_value_new_null());
    fl_value_append_take(strings, entry);
  }
  Set(result, "files", fl_value_ref(files));
  Set(result, "strings", fl_value_ref(strings));
  Set(result, "allowedOperations", fl_value_ref(operations));
  Set(result, "isComplete", fl_value_new_bool(!drag->loading &&
      (drag->key.empty() || drag->portal_resolved)));
  drag->offer = result;
  return fl_value_ref(result);
}
FlValue* Arguments(const StateRef& state, const DragRef& drag, int64_t request, int phase, int64_t target, bool with_offer = false) {
  FlValue* result = fl_value_new_map();
  Set(result, "view", fl_value_new_int(state->view_id));
  Set(result, "generation", fl_value_new_int(state->generation));
  Set(result, "session", fl_value_new_int(drag->session));
  Set(result, "request", fl_value_new_int(request));
  Set(result, "phase", fl_value_new_int(phase));
  Set(result, "target", fl_value_new_int(target));
  Set(result, "operation", fl_value_new_int(drag->operation));
  Set(result, "x", fl_value_new_float(drag->x));
  Set(result, "y", fl_value_new_float(drag->y));
  const auto actions = gdk_drag_context_get_actions(drag->context);
  const int mask = (actions & GDK_ACTION_COPY ? 1 : 0) |
      (actions & GDK_ACTION_MOVE ? 2 : 0) | (actions & GDK_ACTION_LINK ? 4 : 0);
  Set(result, "operationMask", fl_value_new_int(mask));
  if (with_offer) Set(result, "offer", Offer(drag));
  return result;
}

void RequestQuery(const StateRef& state, const DragRef& drag);
void ResolvePortal(const StateRef& state, const DragRef& drag);

void FinishDrop(const StateRef& state, const DragRef& drag, bool success) {
  drag->Finish(success);
  const auto found = state->sources.find(drag->session);
  if (found != state->sources.end() && found->second == drag) state->sources.erase(found);
  if (state->drag == drag) state->drag.reset();
}
void Deliver(const StateRef& state, const DragRef& drag, int64_t request, int64_t target, int32_t operation) {
  drag->operation = target > 0 ? operation : 0;
  const auto action = operation == 1 ? GDK_ACTION_COPY : operation == 2 ? GDK_ACTION_MOVE :
      operation == 3 ? GDK_ACTION_LINK : static_cast<GdkDragAction>(0);
  gdk_drag_status(drag->context, target > 0 ? action : static_cast<GdkDragAction>(0), drag->time);
  if (target <= 0) { FinishDrop(state, drag, false); return; }
  drag->delivered = true;
  state->sources[drag->session] = drag;
  g_autoptr(FlValue) args = Arguments(state, drag, request, 2, target, true);
  // Reply only after the application's asynchronous onDrop finishes.
  state->transport->Invoke("drop", args, [state, drag](FlValue* value) {
    FinishDrop(state, drag, value && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL && fl_value_get_bool(value));
  });
}

void Apply(const QueryRef& query, int64_t target, int32_t operation = 0) {
  auto state = query->state;
  auto drag = query->drag;
  drag->query_pending = false;
  if (!Current(state, drag) || (!drag->inside && !drag->dropping)) return;
  if (query->revision != drag->revision) {
    if (drag->dropping && !drag->key.empty() && !drag->portal_resolved) ResolvePortal(state, drag);
    else RequestQuery(state, drag);
    return;
  }
  const auto action = operation == 1 ? GDK_ACTION_COPY : operation == 2 ? GDK_ACTION_MOVE :
      operation == 3 ? GDK_ACTION_LINK : static_cast<GdkDragAction>(0);
  if (target <= 0 || !(gdk_drag_context_get_actions(drag->context) & action)) target = 0;
  drag->operation = target > 0 ? operation : 0;
  g_autoptr(FlValue) args = Arguments(state, drag, query->request, query->final ? 2 : 1, target);
  Invoke(state, "feedback", args);
  if (query->final) {
    Deliver(state, drag, query->request, target, operation);
  } else {
    gdk_drag_status(drag->context, target > 0 ? action : static_cast<GdkDragAction>(0), drag->time);
  }
}

void QueryReceived(const QueryRef& query, FlValue* value) {
  if (query->finished) return;
  query->finished = true;
  if (query->timer) { g_source_remove(query->timer); query->timer = 0; }
  FlValue* target = value && fl_value_get_type(value) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(value, "target") : nullptr;
  FlValue* operation = value && fl_value_get_type(value) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(value, "operation") : nullptr;
  const int64_t selected = target && fl_value_get_type(target) == FL_VALUE_TYPE_INT ? fl_value_get_int(target) : 0;
  const int64_t chosen = operation && fl_value_get_type(operation) == FL_VALUE_TYPE_INT ? fl_value_get_int(operation) : 0;
  if (selected == -1 && !query->offer_snapshot && Current(query->state, query->drag)) {
    query->drag->query_pending = false;
    query->drag->offer_sent = false;
    RequestQuery(query->state, query->drag);
    return;
  }
  if (target && fl_value_get_type(target) == FL_VALUE_TYPE_INT && selected >= 0 &&
      query->offer_snapshot && query->offer_snapshot == query->drag->offer) {
    query->drag->offer_sent = true;
  }
  Apply(query, selected, chosen >= 1 && chosen <= 3 ? static_cast<int32_t>(chosen) : 0);
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
      if (request->state->transport) request->state->transport->Cancel(request->rpc_request);
      Apply(request, 0);
    }
    return G_SOURCE_REMOVE;
  }, new QueryRef(query), [](gpointer data) { delete static_cast<QueryRef*>(data); });
  g_autoptr(FlValue) args = Arguments(state, drag, query->request, query->final ? 2 : 1, 0);
  if (query->final || !drag->offer_sent) {
    query->offer_snapshot = Offer(drag);
    Set(args, "offer", fl_value_ref(query->offer_snapshot));
  }
  query->rpc_request = state->transport->Invoke("query", args, [query](FlValue* value) { QueryReceived(query, value); });
}

void AddPath(const DragRef& drag, const char* path) {
  if (!path || !*path) return;
  if (std::any_of(drag->files.begin(), drag->files.end(), [path](const File& file) { return file.path == path; })) return;
  g_autofree gchar* name = g_path_get_basename(path);
  drag->files.push_back({path, name});
}
void ReadUris(const DragRef& drag, const std::string& text) {
  g_auto(GStrv) uris = g_uri_list_extract_uris(text.c_str());
  for (gchar** uri = uris; uri && *uri; ++uri) {
    g_autofree gchar* hostname = nullptr;
    g_autofree gchar* path = g_filename_from_uri(*uri, &hostname, nullptr);
    if (path && (!hostname || !*hostname || !g_ascii_strcasecmp(hostname, "localhost") ||
                 !g_ascii_strcasecmp(hostname, g_get_host_name()))) AddPath(drag, path);
  }
  if (!drag->files.empty()) drag->has_file = true;
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
  InvalidateOffer(drag);
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
  drag->has_file = g_list_find(const_cast<GList*>(targets), gdk_atom_intern_static_string(kPortal)) != nullptr;
  // Prefer a UTF-8 plain-text representation. GTK converts legacy STRING for us.
  for (const char* type : {kPlain, kUtf8, "text/plain", "COMPOUND_TEXT", "TEXT", kString}) {
    const auto atom = gdk_atom_intern(type, FALSE);
    if (g_list_find(const_cast<GList*>(targets), atom)) {
      drag->string_types.emplace(atom, "text/plain");
      drag->strings.emplace("text/plain", std::nullopt);
      break;
    }
  }
  bool uri_list = g_list_find(const_cast<GList*>(targets), gdk_atom_intern_static_string(kUris)) != nullptr;
  for (const GList* item = targets; item; item = item->next) {
    const auto atom = static_cast<GdkAtom>(item->data);
    g_autofree gchar* name = gdk_atom_name(atom);
    const std::string type = name ? name : "";
    if (type.rfind("text/", 0) == 0 && type.rfind("text/plain", 0) != 0) {
      if (type == "text/x-moz-url" && uri_list) continue;
      const std::string mime = type == "text/x-moz-url" ? kUris : type;
      drag->string_types.emplace(atom, mime);
      drag->strings.emplace(mime, std::nullopt);
    }
    if ((drag->binary_type.empty() && type.rfind("image/", 0) == 0) ||
        type.rfind("application/octet-stream;", 0) == 0) {
      std::string filename;
      if (type.rfind("application/octet-stream;", 0) == 0) {
        // Chromium exports virtual files with a quoted, escaped name parameter.
        g_autoptr(GRegex) pattern = g_regex_new(R"mime(;\s*name=(?:"((?:\\.|[^"])*)"|([^;]+)))mime", G_REGEX_CASELESS, static_cast<GRegexMatchFlags>(0), nullptr);
        GMatchInfo* match = nullptr;
        if (g_regex_match(pattern, type.c_str(), static_cast<GRegexMatchFlags>(0), &match)) {
          g_autofree gchar* quoted = g_match_info_fetch(match, 1);
          g_autofree gchar* unquoted = g_match_info_fetch(match, 2);
          const std::string escaped = quoted && *quoted ? quoted : unquoted ? unquoted : "";
          for (size_t i = 0; i < escaped.size(); ++i) {
            if (escaped[i] == '\\' && i + 1 < escaped.size()) ++i;
            filename += escaped[i];
          }
        }
        if (match) g_match_info_free(match);
        if (filename.empty()) continue;
      }
      drag->binary_type = type;
      drag->binary_mime = type.substr(0, type.find(';'));
      const std::string extension = type == "image/jpeg" ? "jpg" : type == "image/svg+xml" ? "svg" :
          type.substr(type.find('/') + 1);
      drag->binary_name = filename.empty() ? "image." + extension : filename;
    }
  }
  // Named virtual-file MIME types vary per drag. Register the offered types
  // we can actually read, replacing the previous list instead of accumulating
  // one target entry for every filename ever dragged into the window.
  auto* accepted = gtk_target_list_new(nullptr, 0);
  for (const auto& string : drag->string_types) gtk_target_list_add(accepted, string.first, 0, 0);
  const auto portal = gdk_atom_intern_static_string(kPortal);
  if (g_list_find(const_cast<GList*>(targets), portal)) gtk_target_list_add(accepted, portal, 0, 0);
  if (!drag->binary_type.empty()) gtk_target_list_add(accepted, gdk_atom_intern(drag->binary_type.c_str(), FALSE), 0, 0);
  gtk_drag_dest_set_target_list(state->view, accepted);
  gtk_target_list_unref(accepted);
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
  for (const auto& string : drag->string_types) drag->pending.insert(string.first);
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
  if (drag->dropping) return TRUE;
  drag->inside = true; drag->x = x; drag->y = y; drag->time = time; ++drag->revision;
  Load(state, drag); RequestQuery(state, drag);
  return TRUE;
}
static gboolean Drop(GtkWidget*, GdkDragContext* context, gint x, gint y, guint time, gpointer data) {
  const auto state = GetState(data); const auto drag = GetDrag(state, context);
  drag->inside = true; drag->x = x; drag->y = y; drag->time = time; drag->dropping = true; ++drag->revision;
  InvalidateOffer(drag);
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
  auto drag = state->drag;
  if (!drag || drag->context != context) {
    drag.reset();
    for (const auto& entry : state->sources) {
      if (entry.second->context == context) { drag = entry.second; break; }
    }
  }
  if (!drag || drag->finished || state->closed) return;
  const GdkAtom target = gtk_selection_data_get_target(selection);
  const gint length = gtk_selection_data_get_length(selection);
  const auto* bytes = gtk_selection_data_get_data(selection);
  g_autofree gchar* target_name = gdk_atom_name(target);
  if (target_name && drag->binary_type == target_name && !drag->pending_reads.empty()) {
    if (drag->read_timer) { g_source_remove(drag->read_timer); drag->read_timer = 0; }
    const auto pending = std::move(drag->pending_reads);
    drag->pending_reads.clear();
    auto content = std::make_shared<std::vector<uint8_t>>();
    const bool readable = length >= 0 && (bytes || length == 0);
    if (readable && length) content->assign(bytes, bytes + length);
    if (readable) drag->binary_data = content;
    for (const auto& open : pending) {
      if (readable) {
        const int64_t id = ++state->next_reader;
        drag->readers.emplace(id, Reader{content, std::min(open.start, content->size())});
        g_autoptr(FlValue) value = fl_value_new_int(id);
        open.call->Success(value);
      } else open.call->Error("source_expired", "Dropped selection is no longer available");
    }
    return;
  }
  if (!Current(state, drag) || !drag->pending.erase(target)) return;
  if (length >= 0 && (bytes || length == 0)) {
    std::string text;
    if (target == gdk_atom_intern_static_string(kPortal) || target == gdk_atom_intern_static_string(kUris)) {
      if (length) text.assign(reinterpret_cast<const char*>(bytes), length);
      while (!text.empty() && text.back() == '\0') text.pop_back();
    } else if (drag->string_types[target] == "text/plain") {
      g_autofree guchar* value = gtk_selection_data_get_text(selection);
      if (value) text = reinterpret_cast<const char*>(value);
    } else if (target_name && !strcmp(target_name, "text/x-moz-url")) {
      const char* encoding = length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff ? "UTF-16BE" : "UTF-16LE";
      const size_t bom = length >= 2 && ((bytes[0] == 0xff && bytes[1] == 0xfe) || (bytes[0] == 0xfe && bytes[1] == 0xff)) ? 2 : 0;
      g_autofree gchar* value = length > 0 ? g_convert(reinterpret_cast<const char*>(bytes) + bom, length - bom, "UTF-8", encoding, nullptr, nullptr, nullptr) : nullptr;
      if (value) text = value;
      text = text.substr(0, text.find_first_of("\r\n"));
    } else if (length >= 2 && ((bytes[0] == 0xff && bytes[1] == 0xfe) || (bytes[0] == 0xfe && bytes[1] == 0xff))) {
      // HTML and other text targets can supply UTF-16 with a byte-order mark.
      const char* encoding = bytes[0] == 0xfe ? "UTF-16BE" : "UTF-16LE";
      g_autofree gchar* value = g_convert(reinterpret_cast<const char*>(bytes) + 2, length - 2,
          "UTF-8", encoding, nullptr, nullptr, nullptr);
      if (value) text = value;
    } else if (length) {
      text.assign(reinterpret_cast<const char*>(bytes), length);
      while (!text.empty() && text.back() == '\0') text.pop_back();
    }
    if (g_utf8_validate(text.c_str(), text.size(), nullptr)) {
      if (target == gdk_atom_intern_static_string(kPortal)) drag->key = text;
      else {
        const auto mime = drag->string_types.find(target);
        if (mime != drag->string_types.end()) drag->strings[mime->second] = text;
        if (mime != drag->string_types.end() && mime->second == kUris) ReadUris(drag, text);
      }
    }
  }
  if (drag->pending.empty()) {
    drag->loading = false;
    drag->has_file = !drag->files.empty() || !drag->key.empty();
    InvalidateOffer(drag);
    ++drag->revision;
    RequestQuery(state, drag);
  }
}
static int64_t Integer(FlValue* args, const char* key, int64_t fallback = -1) {
  FlValue* value = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(args, key) : nullptr;
  return value && fl_value_get_type(value) == FL_VALUE_TYPE_INT ? fl_value_get_int(value) : fallback;
}
static void ReadSource(const StateRef& state, const FfiCallRef& call) {
  auto* args = call->args;
  auto* value = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(args, "op") : nullptr;
  const std::string op = value && fl_value_get_type(value) == FL_VALUE_TYPE_STRING ? fl_value_get_string(value) : "";
  const auto source = state->sources.find(Integer(args, "session"));
  const auto drag = source == state->sources.end() ? nullptr : source->second;
  const bool current = !state->closed && drag && !drag->finished && Integer(args, "generation") == state->generation &&
      Integer(args, "session") == drag->session;
  if (!current) {
    call->Error("source_expired", "Dropped source is no longer available"); return;
  }
  const int64_t stream = Integer(args, "stream");
  if (op == "close") {
    drag->readers.erase(stream); call->Success(nullptr); return;
  }
  if (op == "read") {
    auto found = drag->readers.find(stream);
    const int64_t count = Integer(args, "count");
    if (found == drag->readers.end() || count <= 0 || count > 65536) {
      call->Error("source_expired", "Dropped reader is no longer available"); return;
    }
    auto& reader = found->second;
    const size_t length = std::min(static_cast<size_t>(count), reader.bytes->size() - reader.offset);
    g_autoptr(FlValue) bytes = fl_value_new_uint8_list(length ? reader.bytes->data() + reader.offset : nullptr, length);
    reader.offset += length;
    call->Success(bytes); return;
  }
  if (Integer(args, "source") != 0 || drag->binary_type.empty()) {
    call->Error("source_expired", "Dropped item is no longer available"); return;
  }
  if (op == "stat") {
    g_autoptr(FlValue) metadata = fl_value_new_map();
    Set(metadata, "name", fl_value_new_string(drag->binary_name.c_str()));
    if (drag->binary_data) Set(metadata, "length", fl_value_new_int(drag->binary_data->size()));
    call->Success(metadata); return;
  }
  if (op == "open") {
    const int64_t start = Integer(args, "start", 0);
    if (start < 0) { call->Error("invalid_range", "Invalid read offset"); return; }
    if (drag->binary_data) {
      const int64_t id = ++state->next_reader;
      drag->readers.emplace(id, Reader{drag->binary_data, std::min(static_cast<size_t>(start), drag->binary_data->size())});
      g_autoptr(FlValue) value = fl_value_new_int(id);
      call->Success(value); return;
    }
    drag->pending_reads.push_back({call, static_cast<size_t>(start)});
    if (drag->pending_reads.size() == 1) {
      drag->read_timer = g_timeout_add_full(G_PRIORITY_DEFAULT, 10000, [](gpointer data) -> gboolean {
        const auto drag = *static_cast<DragRef*>(data);
        drag->read_timer = 0; drag->ReleaseReaders();
        return G_SOURCE_REMOVE;
      }, new DragRef(drag), [](gpointer data) { delete static_cast<DragRef*>(data); });
      gtk_drag_get_data(state->view, drag->context, gdk_atom_intern(drag->binary_type.c_str(), FALSE), drag->time);
    }
    return;
  }
  call->NotImplemented();
}

static void HandleCall(const StateRef& state, const FfiCallRef& call) {
  if (strcmp(call->name.c_str(), "readSource") == 0) { ReadSource(state, call); return; }
  if (strcmp(call->name.c_str(), "initialize") == 0) {
    auto* args = call->args;
    FlValue* id = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(args, "view") : nullptr;
    if (!id || fl_value_get_type(id) != FL_VALUE_TYPE_INT || fl_value_get_int(id) != state->view_id) {
      call->Error("unsupported_view", "Flutter view is not attached"); return;
    }
    state->ResetSources();
    ++state->generation;
    g_autoptr(FlValue) result = fl_value_new_map(); Set(result, "view", fl_value_new_int(state->view_id));
    Set(result, "generation", fl_value_new_int(state->generation));
    call->Success(result);
  } else call->NotImplemented();
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
  state->transport = std::make_unique<FfiTransport>(reinterpret_cast<int64_t>(fl_view_get_engine(view)),
    [weak = std::weak_ptr<State>(state)](const FfiCallRef& call) {
      if (const auto state = weak.lock()) HandleCall(state, call);
      else call->Error("source_expired", "Flutter view has been destroyed");
    });
  GtkTargetEntry targets[] = {{const_cast<char*>(kPortal), 0, 0}, {const_cast<char*>(kUris), 0, 1},
    {const_cast<char*>(kPlain), 0, 2}, {const_cast<char*>(kUtf8), 0, 3},
    {const_cast<char*>("text/plain"), 0, 4}, {const_cast<char*>(kString), 0, 5}};
  gtk_drag_dest_set(GTK_WIDGET(view), static_cast<GtkDestDefaults>(0), targets, G_N_ELEMENTS(targets),
      static_cast<GdkDragAction>(GDK_ACTION_COPY | GDK_ACTION_MOVE | GDK_ACTION_LINK));
  gtk_drag_dest_set_track_motion(GTK_WIDGET(view), TRUE);
  g_signal_connect_object(view, "drag-motion", G_CALLBACK(Motion), plugin, static_cast<GConnectFlags>(0));
  g_signal_connect_object(view, "drag-drop", G_CALLBACK(Drop), plugin, static_cast<GConnectFlags>(0));
  g_signal_connect_object(view, "drag-leave", G_CALLBACK(Leave), plugin, static_cast<GConnectFlags>(0));
  g_signal_connect_object(view, "drag-data-received", G_CALLBACK(DataReceived), plugin, static_cast<GConnectFlags>(0));
  g_signal_connect_object(fl_view_get_engine(view), "pre-engine-restart", G_CALLBACK(+[](FlEngine*, gpointer data) {
    GetState(data)->ResetSources();
  }), plugin, static_cast<GConnectFlags>(0));
  g_object_set_data_full(G_OBJECT(view), "desktop_drop_plugin", plugin, g_object_unref);
}
