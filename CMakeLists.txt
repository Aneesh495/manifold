cmake_minimum_required(VERSION 3.16)
project(manifold LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Compiler optimization and warnings
if(CMAKE_C_COMPILER_ID MATCHES "Clang|AppleClang|GNU")
    add_compile_options(-Wall -Wextra -Wpedantic -O3 -fPIC)
endif()

include_directories(
    include
    runtime
    c_fastpath
)

# Core library source files (compiled via eC bridge)
file(GLOB_RECURSE C_FASTPATH_SRCS "c_fastpath/*.c")
file(GLOB_RECURSE RUNTIME_SRCS "runtime/*.c")

add_library(manifold_core STATIC
    ${C_FASTPATH_SRCS}
    ${RUNTIME_SRCS}
)

# Central Gateway executable
add_executable(manifold_app
    src/main.c
)
target_link_libraries(manifold_app PRIVATE manifold_core)
set_target_properties(manifold_app PROPERTIES OUTPUT_NAME manifold RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

# Interactive Terminal executable
add_executable(manifold_terminal
    src/app/DiagTerminal.c
)
target_link_libraries(manifold_terminal PRIVATE manifold_core)
set_target_properties(manifold_terminal PROPERTIES OUTPUT_NAME manifold_terminal RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

# Test suite executable
add_executable(manifold_test
    tests/test_runner.c
)
target_link_libraries(manifold_test PRIVATE manifold_core)
set_target_properties(manifold_test PROPERTIES OUTPUT_NAME manifold_test RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

# Enable CTest
enable_testing()
add_test(NAME ManifoldAllTests COMMAND manifold_test)
