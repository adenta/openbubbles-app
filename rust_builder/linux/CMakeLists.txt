cmake_minimum_required(VERSION 3.10)
project(rust_lib_bluebubbles LANGUAGES CXX)

# Linux uses the exact official engine. Never invoke Cargo for this backend.
# Flutter reaches us via .plugin_symlinks, so resolve the plugin directory first.
get_filename_component(PLUGIN_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." REALPATH)
get_filename_component(APP_ROOT "${PLUGIN_ROOT}/.." ABSOLUTE)
set(ENGINE "$ENV{OPENBUBBLES_ENGINE_LIBRARY}")
if(NOT IS_ABSOLUTE "${ENGINE}" OR NOT EXISTS "${ENGINE}")
  message(FATAL_ERROR "Official engine missing. Run bin/build-linux-dev.")
endif()
find_program(NODE_EXECUTABLE node REQUIRED)
execute_process(COMMAND "${NODE_EXECUTABLE}" "${APP_ROOT}/bin/official-engine.mjs" verify "${ENGINE}"
  RESULT_VARIABLE ENGINE_STATUS OUTPUT_VARIABLE ENGINE_OUTPUT ERROR_VARIABLE ENGINE_ERROR)
if(NOT ENGINE_STATUS EQUAL 0)
  message(FATAL_ERROR "Official engine validation failed: ${ENGINE_OUTPUT}${ENGINE_ERROR}")
endif()
set(rust_lib_bluebubbles_bundled_libraries "${ENGINE}" PARENT_SCOPE)
