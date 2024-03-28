cmake_minimum_required(VERSION 3.28)
project(Vhashmap)
find_package(verilator HINTS $ENV{VERILATOR_ROOT})
add_library(Vhashmap STATIC)
verilate(Vhashmap SOURCES column.sv crc.sv hashmap.sv ram.sv PREFIX Vhashmap TRACE_FST TRACE_STRUCTS)

get_property(hashmap_include_dirs TARGET Vhashmap PROPERTY INTERFACE_INCLUDE_DIRECTORIES)
set(headers "")

unset(h)
find_file(h Vhashmap.h PATHS ${hashmap_include_dirs} REQUIRED NO_CACHE)
list(APPEND headers "${h}")

unset(h)
find_file(h verilated.h PATHS ${hashmap_include_dirs} REQUIRED NO_CACHE)
list(APPEND headers "${h}")

unset(h)
find_file(h verilatedos.h PATHS ${hashmap_include_dirs} REQUIRED NO_CACHE)
list(APPEND headers "${h}")

unset(h)
find_file(h verilated_config.h PATHS ${hashmap_include_dirs} REQUIRED NO_CACHE)
list(APPEND headers "${h}")

unset(h)
find_file(h verilated_types.h PATHS ${hashmap_include_dirs} REQUIRED NO_CACHE)
list(APPEND headers "${h}")

unset(h)
find_file(h verilated_funcs.h PATHS ${hashmap_include_dirs} REQUIRED NO_CACHE)
list(APPEND headers "${h}")

unset(h)
find_file(h verilated_fst_c.h PATHS ${hashmap_include_dirs} REQUIRED NO_CACHE)
list(APPEND headers "${h}")

unset(h)
find_file(h verilated_trace.h PATHS ${hashmap_include_dirs} REQUIRED NO_CACHE)
list(APPEND headers "${h}")

install(TARGETS Vhashmap)
install(FILES ${headers} DESTINATION include)
