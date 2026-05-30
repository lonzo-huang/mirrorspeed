#include "include/amneziawg_flutter/amneziawg_flutter_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "amneziawg_flutter_plugin.h"

void AmneziawgFlutterPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  amneziawg_flutter::AmneziawgFlutterPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
