cmake_minimum_required(VERSION 3.28)
project(Vkvs)
find_package(verilator HINTS $ENV{VERILATOR_ROOT})
add_library(Vkvs STATIC)
verilate(Vkvs SOURCES column.sv crc.sv kvs.sv ram.sv PREFIX Vkvs TRACE_FST TRACE_STRUCTS)

get_property(kvs_include_dirs TARGET Vkvs PROPERTY INTERFACE_INCLUDE_DIRECTORIES)
set(headers "")

unset(h)
find_file(h Vkvs.h PATHS ${kvs_include_dirs} REQUIRED NO_CACHE)
list(APPEND headers "${h}")

unset(h)
find_file(h verilated.h PATHS ${kvs_include_dirs} REQUIRED NO_CACHE)
list(APPEND headers "${h}")

unset(h)
find_file(h verilatedos.h PATHS ${kvs_include_dirs} REQUIRED NO_CACHE)
list(APPEND headers "${h}")

unset(h)
find_file(h verilated_config.h PATHS ${kvs_include_dirs} REQUIRED NO_CACHE)
list(APPEND headers "${h}")

unset(h)
find_file(h verilated_types.h PATHS ${kvs_include_dirs} REQUIRED NO_CACHE)
list(APPEND headers "${h}")

unset(h)
find_file(h verilated_funcs.h PATHS ${kvs_include_dirs} REQUIRED NO_CACHE)
list(APPEND headers "${h}")

unset(h)
find_file(h verilated_fst_c.h PATHS ${kvs_include_dirs} REQUIRED NO_CACHE)
list(APPEND headers "${h}")

unset(h)
find_file(h verilated_trace.h PATHS ${kvs_include_dirs} REQUIRED NO_CACHE)
list(APPEND headers "${h}")

install(TARGETS Vkvs)
install(FILES ${headers} DESTINATION include)
