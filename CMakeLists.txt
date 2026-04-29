cmake_minimum_required(VERSION 3.20)

if(APPLE)
    project(MetalCMakeDemo LANGUAGES C CXX OBJC OBJCXX)
else()
    project(MetalCMakeDemo LANGUAGES C CXX)
endif()


set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(APP_NAME MetalCMakeDemo)

if(APPLE)
    set(SOURCES
        src/main.mm
        src/AppDelegate.mm
        src/Renderer.mm
        src/OpenGLRenderer.mm
    )

    set(HEADERS
        src/AppDelegate.h
        src/Renderer.h
        src/OpenGLRenderer.h
    )

    set(METAL_SHADER
        shaders/triangle.metal
    )

    add_executable(${APP_NAME} MACOSX_BUNDLE
        ${SOURCES}
        ${HEADERS}
        ${METAL_SHADER}
    )

    target_compile_options(${APP_NAME} PRIVATE
        "-fobjc-arc"
    )

    target_compile_definitions(${APP_NAME} PRIVATE
        GL_SILENCE_DEPRECATION=1
    )

    find_library(COCOA_FRAMEWORK Cocoa REQUIRED)
    find_library(METAL_FRAMEWORK Metal REQUIRED)
    find_library(METALFX_FRAMEWORK MetalFX REQUIRED)
    find_library(QUARTZCORE_FRAMEWORK QuartzCore REQUIRED)
    find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
    find_library(OPENGL_FRAMEWORK OpenGL REQUIRED)

    target_link_libraries(${APP_NAME} PRIVATE
        ${COCOA_FRAMEWORK}
        ${METAL_FRAMEWORK}
        ${METALFX_FRAMEWORK}
        ${QUARTZCORE_FRAMEWORK}
        ${FOUNDATION_FRAMEWORK}
        ${OPENGL_FRAMEWORK}
    )

    set_source_files_properties(${METAL_SHADER} PROPERTIES
        MACOSX_PACKAGE_LOCATION Resources
    )

    set_target_properties(${APP_NAME} PROPERTIES
        MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/Info.plist
        MACOSX_BUNDLE_GUI_IDENTIFIER "com.example.metalcmakedemo"
        MACOSX_DEPLOYMENT_TARGET "14.0"
        XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.example.metalcmakedemo"
    )
else()
    add_executable(${APP_NAME}
        src/OpenGLCrossPlatformMain.cpp
    )

    find_package(OpenGL REQUIRED)
    find_package(glfw3 REQUIRED)

    target_link_libraries(${APP_NAME} PRIVATE
        OpenGL::GL
        glfw
    )
endif()