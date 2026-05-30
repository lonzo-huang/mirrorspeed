cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "amneziawg_flutter")
project(${PROJECT_NAME} LANGUAGES CXX)

# ── Build mode ───────────────────────────────────────────────────────────────
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── Sources ───────────────────────────────────────────────────────────────────
add_library(${PROJECT_NAME} SHARED
  "amneziawg_flutter_plugin.cpp"
  "amneziawg_flutter_plugin_c_api.cpp"
)

# ── Include dirs ──────────────────────────────────────────────────────────────
target_include_directories(${PROJECT_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

# ── Flutter plugin interface ───────────────────────────────────────────────────
# The ephemeral Flutter headers are injected by the Flutter Windows toolchain.
set(flutter_wrapper_plugin flutter_wrapper_plugin)

apply_standard_settings(${PROJECT_NAME})

set_target_properties(${PROJECT_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)

target_compile_definitions(${PROJECT_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PROJECT_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_link_libraries(${PROJECT_NAME} PRIVATE
  ${flutter_wrapper_plugin}
  advapi32  # Windows SCM (service control manager)
)

# ── Bundled AWG binaries ──────────────────────────────────────────────────────
# Place the following AmneziaWG Windows binaries in:
#   packages/amneziawg_flutter/windows/bin/
#
# Required files (build from https://github.com/amnezia-vpn/amneziawg-windows):
#   amneziawg_svc.exe   — tunnel service executable
#   tunnel.dll          — AWG tunnel library
#   wireguard.dll       — WireGuard NT adapter library
#   wintun.dll          — WinTun driver shim
#
# They are copied next to the Flutter app .exe during packaging.

set(AWG_BIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/bin")
if(EXISTS "${AWG_BIN_DIR}")
  file(GLOB AWG_BINARIES "${AWG_BIN_DIR}/*.exe" "${AWG_BIN_DIR}/*.dll")
  foreach(BIN ${AWG_BINARIES})
    install(FILES "${BIN}" DESTINATION ".")
  endforeach()
  # Also copy at build time so debug runs work
  foreach(BIN ${AWG_BINARIES})
    get_filename_component(BIN_NAME "${BIN}" NAME)
    add_custom_command(
      TARGET ${PROJECT_NAME} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${BIN}"
        "$<TARGET_FILE_DIR:${PROJECT_NAME}>/${BIN_NAME}"
    )
  endforeach()
endif()
