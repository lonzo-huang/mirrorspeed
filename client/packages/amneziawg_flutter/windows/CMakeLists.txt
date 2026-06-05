cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "amneziawg_flutter")
project(${PROJECT_NAME} LANGUAGES CXX)

# ── Build mode ───────────────────────────────────────────────────────────────
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Flutter Windows expects the library target to be named <plugin>_plugin.
set(PLUGIN_NAME "${PROJECT_NAME}_plugin")

# ── Sources ───────────────────────────────────────────────────────────────────
add_library(${PLUGIN_NAME} SHARED
  "amneziawg_flutter_plugin.cpp"
  "amneziawg_flutter_plugin_c_api.cpp"
)

# ── Include dirs ──────────────────────────────────────────────────────────────
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

# ── Flutter plugin interface ───────────────────────────────────────────────────
# The ephemeral Flutter headers are injected by the Flutter Windows toolchain.
set(flutter_wrapper_plugin flutter_wrapper_plugin)

apply_standard_settings(${PLUGIN_NAME})

# Force MSVC to read source files as UTF-8 (avoids C4819 on Chinese Windows)
if(MSVC)
  target_compile_options(${PLUGIN_NAME} PRIVATE /utf-8)
endif()

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE
  ${flutter_wrapper_plugin}
  advapi32  # Windows SCM (service control manager)
)

# ── Bundled AWG binaries ──────────────────────────────────────────────────────
# Place the AmneziaWG Windows runtime binaries in:
#   packages/amneziawg_flutter/windows/bin/
#
# Required files:
#   amneziawg_svc.exe   — tunnel service host (built from amneziawg-windows;
#                         registered as a Windows service by the plugin)
#   wintun.dll          — WinTun userspace TUN adapter (official signed build)
#
# AmneziaWG runs in userspace (amneziawg-go) over WinTun, so neither tunnel.dll
# nor a WireGuard-NT driver (wireguard.dll) is needed on Windows.
#
# Files are exported via the Flutter <plugin>_bundled_libraries convention; the
# Flutter runner CMake then installs them next to the app .exe and copies them
# for `flutter run`. (A raw install(FILES DESTINATION ".") fails the INSTALL
# target with "file cannot create directory".)

set(AWG_BIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/bin")
if(EXISTS "${AWG_BIN_DIR}")
  file(GLOB AWG_BINARIES "${AWG_BIN_DIR}/*.exe" "${AWG_BIN_DIR}/*.dll")
  set(amneziawg_flutter_bundled_libraries
    "${AWG_BINARIES}"
    PARENT_SCOPE
  )
endif()
