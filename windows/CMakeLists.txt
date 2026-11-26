# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(whatisthat LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "whatisthat")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd4100)
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Pre-stage Microsoft.ML.OnnxRuntime from NuGet so flutter_onnxruntime does not
# attempt to fetch the unavailable v1.28.3 GitHub release archive.
set(_ORT_DEST_DIR "${CMAKE_BINARY_DIR}/plugins/flutter_onnxruntime/onnxruntime/onnxruntime-win-x64-1.28.3")
if(NOT EXISTS "${_ORT_DEST_DIR}/include/onnxruntime_cxx_api.h")
  set(_ORT_NUPKG "${CMAKE_BINARY_DIR}/onnxruntime.1.28.0.nupkg.zip")
  set(_ORT_TMP "${CMAKE_BINARY_DIR}/_ort_nuget_extract")
  message(STATUS "Downloading Microsoft.ML.OnnxRuntime 1.28.0 from NuGet...")
  file(DOWNLOAD
    "https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/1.28.0/microsoft.ml.onnxruntime.1.28.0.nupkg"
    "${_ORT_NUPKG}"
    STATUS _ORT_DL_STATUS
    SHOW_PROGRESS
  )
  list(GET _ORT_DL_STATUS 0 _ORT_DL_CODE)
  if(NOT _ORT_DL_CODE EQUAL 0)
    message(FATAL_ERROR "Failed to download ONNX Runtime NuGet package: ${_ORT_DL_STATUS}")
  endif()
  file(MAKE_DIRECTORY "${_ORT_TMP}")
  execute_process(
    COMMAND ${CMAKE_COMMAND} -E tar xf "${_ORT_NUPKG}"
    WORKING_DIRECTORY "${_ORT_TMP}"
    RESULT_VARIABLE _ORT_TAR_RES
  )
  if(NOT _ORT_TAR_RES EQUAL 0)
    message(FATAL_ERROR "Failed to extract ONNX Runtime NuGet package")
  endif()
  file(MAKE_DIRECTORY "${_ORT_DEST_DIR}/include" "${_ORT_DEST_DIR}/lib")
  file(COPY "${_ORT_TMP}/build/native/include/" DESTINATION "${_ORT_DEST_DIR}/include")
  file(COPY "${_ORT_TMP}/runtimes/win-x64/native/onnxruntime.dll"
            "${_ORT_TMP}/runtimes/win-x64/native/onnxruntime.lib"
            "${_ORT_TMP}/runtimes/win-x64/native/onnxruntime_providers_shared.dll"
       DESTINATION "${_ORT_DEST_DIR}/lib")
  file(REMOVE "${_ORT_NUPKG}")
  file(REMOVE_RECURSE "${_ORT_TMP}")
endif()

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

if(EXISTS "${_ORT_DEST_DIR}/lib/onnxruntime_providers_shared.dll")
  install(FILES "${_ORT_DEST_DIR}/lib/onnxruntime_providers_shared.dll"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the hook/build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
