# android/app/src/main/cpp/CMakeLists.txt

cmake_minimum_required(VERSION 3.22.1)
project("railwaypagerdemod")

add_library(${CMAKE_PROJECT_NAME} SHARED
        demod.cpp
        demod.h
        audio_demod.cpp
        audio_demod.h
        audio_fft.cpp
        audio_fft.h
        native-lib.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/dsp/firfilter.cpp
        )

target_link_libraries(${CMAKE_PROJECT_NAME}
        android
        log
        m)

add_definitions(-DSDRBASE_API=)
include_directories(
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/fcdlib
)