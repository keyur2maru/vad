# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# Project-level configuration.
set(PROJECT_NAME "vad")
project(${PROJECT_NAME} LANGUAGES CXX)

# Bundle ALL architectures - runtime detection will choose the correct one
set(X64_LIB_PATH "${CMAKE_CURRENT_SOURCE_DIR}/x64/libonnxruntime.so.1.22.0")
set(ARM64_LIB_PATH "${CMAKE_CURRENT_SOURCE_DIR}/arm64/libonnxruntime.so.1.22.0")

# Collect all available libraries
set(BUNDLED_LIBS)

if(EXISTS "${X64_LIB_PATH}")
  list(APPEND BUNDLED_LIBS "${X64_LIB_PATH}")
endif()

if(EXISTS "${ARM64_LIB_PATH}")
  list(APPEND BUNDLED_LIBS "${ARM64_LIB_PATH}")
endif()

# Ensure at least one library exists
if(NOT BUNDLED_LIBS)
  message(FATAL_ERROR "No ONNX Runtime libraries found. Expected at least one of: ${X64_LIB_PATH}, ${ARM64_LIB_PATH}")
endif()

# List of absolute paths to libraries that should be bundled with the plugin.
set(vad_bundled_libraries
  ${BUNDLED_LIBS}
  PARENT_SCOPE
)