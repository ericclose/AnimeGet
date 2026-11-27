#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#ifdef HAVE_WEBKIT2GTK
#include <webkit2/webkit2.h>
#endif

#include <cstring>
#include <string>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

#ifdef HAVE_WEBKIT2GTK
namespace {

struct LinuxWebViewResolveCtx {
  FlMethodCall* method_call = nullptr;
  GtkWidget* window = nullptr;
  WebKitWebView* web_view = nullptr;
  WebKitUserContentManager* content_manager = nullptr;
  guint timeout_id = 0;
  gulong msg_handler_id = 0;
  gulong resource_handler_id = 0;
  gulong tls_handler_id = 0;
  bool finished = false;
};

static bool IsLikelyMediaResourceUrl(const std::string& url) {
  if (url.rfind("http://", 0) != 0 && url.rfind("https://", 0) != 0) {
    return false;
  }
  return url.find(".m3u8") != std::string::npos ||
         url.find("/m3u8/") != std::string::npos ||
         url.find(".mp4") != std::string::npos;
}

static void FinishLinuxWebViewResolve(LinuxWebViewResolveCtx* ctx,
                                      const char* resolved_url) {
  if (!ctx || ctx->finished) return;
  ctx->finished = true;

  if (ctx->timeout_id != 0) {
    g_source_remove(ctx->timeout_id);
    ctx->timeout_id = 0;
  }

  if (ctx->content_manager != nullptr) {
    if (ctx->msg_handler_id != 0) {
      g_signal_handler_disconnect(ctx->content_manager, ctx->msg_handler_id);
      ctx->msg_handler_id = 0;
    }
    webkit_user_content_manager_unregister_script_message_handler(
        ctx->content_manager, "videoCaptured");
  }

  if (ctx->web_view != nullptr) {
    if (ctx->resource_handler_id != 0) {
      g_signal_handler_disconnect(ctx->web_view, ctx->resource_handler_id);
      ctx->resource_handler_id = 0;
    }
    if (ctx->tls_handler_id != 0) {
      g_signal_handler_disconnect(ctx->web_view, ctx->tls_handler_id);
      ctx->tls_handler_id = 0;
    }
    webkit_web_view_stop_loading(ctx->web_view);
  }

  if (ctx->method_call != nullptr) {
    g_autoptr(FlValue) result =
        resolved_url != nullptr ? fl_value_new_string(resolved_url)
                                : fl_value_new_null();
    fl_method_call_respond_success(ctx->method_call, result, nullptr);
    g_object_unref(ctx->method_call);
    ctx->method_call = nullptr;
  }

  if (ctx->window != nullptr) {
    gtk_widget_destroy(ctx->window);
    ctx->window = nullptr;
  }

  delete ctx;
}

static gboolean OnResolveTimeout(gpointer user_data) {
  auto* ctx = static_cast<LinuxWebViewResolveCtx*>(user_data);
  ctx->timeout_id = 0;
  FinishLinuxWebViewResolve(ctx, nullptr);
  return G_SOURCE_REMOVE;
}

static void OnScriptMessageReceived(WebKitUserContentManager* manager,
                                    WebKitJavascriptResult* js_result,
                                    gpointer user_data) {
  auto* ctx = static_cast<LinuxWebViewResolveCtx*>(user_data);
  if (ctx->finished || js_result == nullptr) return;

  JSCValue* value = webkit_javascript_result_get_js_value(js_result);
  if (value != nullptr && jsc_value_is_string(value)) {
    g_autofree gchar* str = jsc_value_to_string(value);
    if (str != nullptr && std::strlen(str) > 0) {
      FinishLinuxWebViewResolve(ctx, str);
    }
  }
}

static void OnResourceLoadStarted(WebKitWebView* web_view,
                                  WebKitWebResource* resource,
                                  WebKitURIRequest* request,
                                  gpointer user_data) {
  auto* ctx = static_cast<LinuxWebViewResolveCtx*>(user_data);
  if (ctx->finished || request == nullptr) return;

  const gchar* uri = webkit_uri_request_get_uri(request);
  if (uri != nullptr && IsLikelyMediaResourceUrl(uri)) {
    FinishLinuxWebViewResolve(ctx, uri);
  }
}

static gboolean OnLoadFailedWithTlsErrors(WebKitWebView* web_view,
                                          gchar* failing_uri,
                                          GTlsCertificate* certificate,
                                          GTlsCertificateFlags errors,
                                          gpointer user_data) {
  if (failing_uri != nullptr && certificate != nullptr) {
    g_autoptr(GUri) parsed = g_uri_parse(failing_uri, G_URI_FLAGS_NONE, nullptr);
    if (parsed != nullptr && g_uri_get_host(parsed) != nullptr) {
      webkit_web_context_allow_tls_certificate_for_host(
          webkit_web_view_get_context(web_view), certificate,
          g_uri_get_host(parsed));
      webkit_web_view_load_uri(web_view, failing_uri);
      return TRUE;
    }
  }
  return FALSE;
}

static void HandleLinuxWebViewMethodCall(FlMethodChannel* channel,
                                         FlMethodCall* method_call,
                                         gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  if (std::strcmp(method, "resolveVideoUrl") != 0) {
    fl_method_call_respond_not_implemented(method_call, nullptr);
    return;
  }

  FlValue* args = fl_method_call_get_args(method_call);
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    fl_method_call_respond_success(method_call, fl_value_new_null(), nullptr);
    return;
  }

  FlValue* url_val = fl_value_lookup_string(args, "url");
  FlValue* referer_val = fl_value_lookup_string(args, "referer");
  FlValue* ua_val = fl_value_lookup_string(args, "userAgent");
  FlValue* hook_val = fl_value_lookup_string(args, "hookScript");
  FlValue* timeout_val = fl_value_lookup_string(args, "timeoutSeconds");

  if (url_val == nullptr || fl_value_get_type(url_val) != FL_VALUE_TYPE_STRING) {
    fl_method_call_respond_success(method_call, fl_value_new_null(), nullptr);
    return;
  }

  const gchar* url = fl_value_get_string(url_val);
  const gchar* referer =
      (referer_val != nullptr &&
       fl_value_get_type(referer_val) == FL_VALUE_TYPE_STRING)
          ? fl_value_get_string(referer_val)
          : "";
  const gchar* user_agent =
      (ua_val != nullptr && fl_value_get_type(ua_val) == FL_VALUE_TYPE_STRING)
          ? fl_value_get_string(ua_val)
          : "";
  const gchar* hook_script =
      (hook_val != nullptr &&
       fl_value_get_type(hook_val) == FL_VALUE_TYPE_STRING)
          ? fl_value_get_string(hook_val)
          : "";
  int timeout_sec = 30;
  if (timeout_val != nullptr &&
      fl_value_get_type(timeout_val) == FL_VALUE_TYPE_INT) {
    timeout_sec = static_cast<int>(fl_value_get_int(timeout_val));
  }

  auto* ctx = new LinuxWebViewResolveCtx();
  ctx->method_call = FL_METHOD_CALL(g_object_ref(method_call));
  ctx->content_manager = webkit_user_content_manager_new();

  webkit_user_content_manager_register_script_message_handler(
      ctx->content_manager, "videoCaptured");
  ctx->msg_handler_id = g_signal_connect(
      ctx->content_manager, "script-message-received::videoCaptured",
      G_CALLBACK(OnScriptMessageReceived), ctx);

  if (std::strlen(hook_script) > 0) {
    WebKitUserScript* script = webkit_user_script_new(
        hook_script, WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES,
        WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, nullptr, nullptr);
    webkit_user_content_manager_add_script(ctx->content_manager, script);
    webkit_user_script_unref(script);
  }

  ctx->web_view = WEBKIT_WEB_VIEW(
      webkit_web_view_new_with_user_content_manager(ctx->content_manager));
  WebKitSettings* settings = webkit_web_view_get_settings(ctx->web_view);
  webkit_settings_set_enable_javascript(settings, TRUE);
  webkit_settings_set_media_playback_requires_user_gesture(settings, FALSE);
  if (std::strlen(user_agent) > 0) {
    webkit_settings_set_user_agent(settings, user_agent);
  }

  ctx->resource_handler_id = g_signal_connect(
      ctx->web_view, "resource-load-started",
      G_CALLBACK(OnResourceLoadStarted), ctx);
  ctx->tls_handler_id = g_signal_connect(
      ctx->web_view, "load-failed-with-tls-errors",
      G_CALLBACK(OnLoadFailedWithTlsErrors), ctx);

  ctx->window = gtk_offscreen_window_new();
  gtk_window_set_default_size(GTK_WINDOW(ctx->window), 800, 600);
  gtk_container_add(GTK_CONTAINER(ctx->window), GTK_WIDGET(ctx->web_view));
  gtk_widget_show_all(ctx->window);

  ctx->timeout_id = g_timeout_add_seconds(
      static_cast<guint>(timeout_sec), OnResolveTimeout, ctx);

  WebKitURIRequest* request = webkit_uri_request_new(url);
  if (std::strlen(referer) > 0) {
    SoupMessageHeaders* headers = webkit_uri_request_get_http_headers(request);
    if (headers != nullptr) {
      soup_message_headers_append(headers, "Referer", referer);
    }
  }
  webkit_web_view_load_request(ctx->web_view, request);
  g_object_unref(request);
}

}  // namespace
#endif  // HAVE_WEBKIT2GTK

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  gtk_window_set_default_size(window, 1280, 720);
  gtk_window_set_title(window, "AnimeGet");

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

#ifdef HAVE_WEBKIT2GTK
  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), "com.animeget/linux_webview",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, HandleLinuxWebViewMethodCall, nullptr, nullptr);
#endif

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
