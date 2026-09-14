#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <json-glib/json-glib.h>

#include "flutter/generated_plugin_registrant.h"

#include <bitsdojo_window_linux/bitsdojo_window_plugin.h>

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Flutter plugins may show the GTK window before Dart's first frame. Restore
// its initial dimensions here, using the same isolated SharedPreferences file
// that Dart updates on user resize. Wayland may ignore later resize requests.
static int saved_dimension(JsonObject* preferences, const char* key, int fallback) {
  if (preferences == nullptr || !json_object_has_member(preferences, key)) return fallback;
  JsonNode* node = json_object_get_member(preferences, key);
  if (!JSON_NODE_HOLDS_VALUE(node)) return fallback;
  GType type = json_node_get_value_type(node);
  if (type != G_TYPE_DOUBLE && type != G_TYPE_INT64) return fallback;
  double value = json_node_get_double(node);
  return value >= 300 && value <= 16384 ? static_cast<int>(value) : fallback;
}

static void restore_initial_size(GtkWindow* window) {
  g_autofree gchar* path = g_build_filename(g_get_user_data_dir(), APPLICATION_ID,
                                           "shared_preferences.json", nullptr);
  g_autoptr(JsonParser) parser = json_parser_new();
  JsonObject* preferences = nullptr;
  if (json_parser_load_from_file(parser, path, nullptr)) {
    JsonNode* root = json_parser_get_root(parser);
    if (JSON_NODE_HOLDS_OBJECT(root)) preferences = json_node_get_object(root);
  }
  int width = saved_dimension(preferences, "flutter.window-width", 1000);
  int height = saved_dimension(preferences, "flutter.window-height", 640);
  GdkMonitor* monitor = gdk_display_get_monitor(gtk_widget_get_display(GTK_WIDGET(window)), 0);
  if (monitor != nullptr) {
    GdkRectangle area;
    gdk_monitor_get_workarea(monitor, &area);
    width = MIN(width, MAX(300, area.width));
    height = MIN(height, MAX(300, area.height));
  }
  gtk_window_set_default_size(window, width, height);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // The app draws its own title bar. Adding a GTK header on Wayland changes
  // the initial height before Dart can hide it. Native decorations can still
  // be enabled later through the existing window_manager setting.
  auto bdw = bitsdojo_window_from(window);
  bdw->setCustomFrame(true);
  gtk_window_set_title(window, "OpenBubbles Dev");
  restore_initial_size(window);
  gtk_widget_realize(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
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

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
