//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <camera_desktop/camera_desktop_plugin.h>
#include <flutter_onnxruntime/flutter_onnxruntime_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) camera_desktop_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "CameraDesktopPlugin");
  camera_desktop_plugin_register_with_registrar(camera_desktop_registrar);
  g_autoptr(FlPluginRegistrar) flutter_onnxruntime_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FlutterOnnxruntimePlugin");
  flutter_onnxruntime_plugin_register_with_registrar(flutter_onnxruntime_registrar);
}
