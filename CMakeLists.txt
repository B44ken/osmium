cmake_minimum_required(VERSION 3.0)

project(osmium)

file(GLOB SOURCES "src/*/*.cpp")
file(GLOB HEADERS "src/*/*.hpp")

include_directories(/mnt/c/mingw_dev_lib/include/)
include_directories(/mnt/c/mingw_dev_lib/lib/)

find_library(SDL2_LIB SDL2)
find_library(SDL2_TTF_LIB SDL2_ttf)
find_library(SDL2_MAIN_LIB SDL2main)

add_executable(osmium src/main.cpp ${SOURCES} ${HEADERS})

target_link_libraries(osmium ${SDL2_LIB} ${SDL2_TTF_LIB} ${SDL2_MAIN_LIB})