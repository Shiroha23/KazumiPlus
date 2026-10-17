#include "website_data.h"
#include <webkit2/webkit2.h>
#include <algorithm>
#include <cctype>
#include <string>

namespace {
std::string Host(std::string value) {
  while (!value.empty() && value.front() == '.') value.erase(0, 1);
  while (!value.empty() && value.back() == '.') value.pop_back();
  std::transform(value.begin(), value.end(), value.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  if (value.compare(0, 4, "www.") == 0) value.erase(0, 4);
  return value;
}
bool Matches(const std::string& domain, const std::string& scope) {
  return domain == scope || (domain.size() > scope.size() &&
      domain.compare(domain.size() - scope.size() - 1, scope.size() + 1, "." + scope) == 0);
}
struct Deletion {
  FlMethodCall* call;
  WebKitWebsiteDataManager* manager;
  GtkWidget* guard;
  std::string host;
  GList* records = nullptr;
};
void Finish(Deletion* deletion, bool success) {
  if (success) fl_method_call_respond_success(deletion->call, nullptr, nullptr);
  else fl_method_call_respond_error(deletion->call, "DELETE_FAILED",
      "Website account data could not be completely deleted", nullptr, nullptr);
  g_list_free_full(deletion->records, [](gpointer record) {
    webkit_website_data_unref(static_cast<WebKitWebsiteData*>(record));
  });
  gtk_widget_destroy(deletion->guard);
  g_object_unref(deletion->guard);
  g_object_unref(deletion->manager);
  g_object_unref(deletion->call);
  delete deletion;
}
void Handle(FlMethodChannel*, FlMethodCall* call, gpointer) {
  if (g_strcmp0(fl_method_call_get_name(call), "deleteAccountData") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  FlValue* args = fl_method_call_get_args(call);
  FlValue* host_value = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
      ? fl_value_lookup_string(args, "host") : nullptr;
  if (!host_value || fl_value_get_type(host_value) != FL_VALUE_TYPE_STRING) {
    fl_method_call_respond_error(call, "INVALID_ARGUMENT", "Website host required", nullptr, nullptr);
    return;
  }
  const auto host = Host(fl_value_get_string(host_value));
  if (host.empty() || host.find_first_of("/\\\" \r\n") != std::string::npos) {
    fl_method_call_respond_error(call, "INVALID_ARGUMENT", "Invalid website host", nullptr, nullptr);
    return;
  }
  auto* context = webkit_web_context_get_default();
  // Initialize the same default context used by desktop_webview_window.
  auto* guard = GTK_WIDGET(g_object_ref_sink(webkit_web_view_new_with_context(context)));
  auto* manager = webkit_web_context_get_website_data_manager(context);
  auto* deletion = new Deletion{FL_METHOD_CALL(g_object_ref(call)),
      WEBKIT_WEBSITE_DATA_MANAGER(g_object_ref(manager)), guard, host};
  webkit_website_data_manager_fetch(manager, WEBKIT_WEBSITE_DATA_ALL, nullptr,
      [](GObject* source, GAsyncResult* result, gpointer data) {
        auto* request = static_cast<Deletion*>(data);
        g_autoptr(GError) error = nullptr;
        auto* records = webkit_website_data_manager_fetch_finish(
            WEBKIT_WEBSITE_DATA_MANAGER(source), result, &error);
        if (error) { Finish(request, false); return; }
        for (auto* item = records; item; item = item->next) {
          auto* record = static_cast<WebKitWebsiteData*>(item->data);
          const auto name = Host(webkit_website_data_get_name(record));
          // Names are grouped by WebKit's public suffix rules.
          if (Matches(name, request->host) || Matches(request->host, name)) {
            request->records = g_list_prepend(request->records, webkit_website_data_ref(record));
          }
        }
        g_list_free_full(records, [](gpointer record) {
          webkit_website_data_unref(static_cast<WebKitWebsiteData*>(record));
        });
        if (!request->records) { Finish(request, true); return; }
        webkit_website_data_manager_remove(request->manager, WEBKIT_WEBSITE_DATA_ALL,
            request->records, nullptr,
            [](GObject* remove_source, GAsyncResult* remove_result, gpointer remove_data) {
              g_autoptr(GError) remove_error = nullptr;
              const bool removed = webkit_website_data_manager_remove_finish(
                  WEBKIT_WEBSITE_DATA_MANAGER(remove_source), remove_result, &remove_error);
              Finish(static_cast<Deletion*>(remove_data), removed && !remove_error);
            }, request);
      }, deletion);
}
}  // namespace

FlMethodChannel* RegisterWebsiteDataChannel(FlBinaryMessenger* messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  auto* channel = fl_method_channel_new(messenger, "com.predidit.kazumi/website_data",
                                        FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, Handle, nullptr, nullptr);
  return channel;
}
