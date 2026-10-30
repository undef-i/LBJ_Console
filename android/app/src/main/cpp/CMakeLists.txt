cmake_minimum_required(VERSION 3.22.1)
project(lbjusb C)

add_library(lbjusb SHARED
    lbj_usb.c
    lbj_pluto.c
    libusb/core.c
    libusb/descriptor.c
    libusb/hotplug.c
    libusb/io.c
    libusb/strerror.c
    libusb/sync.c
    libusb/os/linux_usbfs.c
    libusb/os/events_posix.c
    libusb/os/threads_posix.c
    rtlsdr/librtlsdr.c
    rtlsdr/tuner_e4k.c
    rtlsdr/tuner_fc0012.c
    rtlsdr/tuner_fc0013.c
    rtlsdr/tuner_fc2580.c
    rtlsdr/tuner_r82xx.c
)

target_include_directories(lbjusb PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/libusb
    ${CMAKE_CURRENT_SOURCE_DIR}/rtlsdr
)

target_compile_definitions(lbjusb PRIVATE HAVE_CONFIG_H=1)

target_link_libraries(lbjusb log)
