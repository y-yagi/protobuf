option(protobuf_USE_EXTERNAL_GTEST "Use external Google Test (i.e. not the one in third_party/googletest)" OFF)

option(protobuf_TEST_XML_OUTDIR "Output directory for XML logs from tests." "")

option(protobuf_ABSOLUTE_TEST_PLUGIN_PATH
  "Using absolute test_plugin path in tests" ON)
mark_as_advanced(protobuf_ABSOLUTE_TEST_PLUGIN_PATH)

if (protobuf_USE_EXTERNAL_GTEST)
  find_package(GTest REQUIRED)
else()
  if (NOT EXISTS "${protobuf_SOURCE_DIR}/third_party/googletest/CMakeLists.txt")
    message(FATAL_ERROR
            "Cannot find third_party/googletest directory that's needed to "
            "build tests. If you use git, make sure you have cloned submodules:\n"
            "  git submodule update --init --recursive\n"
            "If instead you want to skip tests, run cmake with:\n"
            "  cmake -Dprotobuf_BUILD_TESTS=OFF\n")
  endif()

  set(googlemock_source_dir "${protobuf_SOURCE_DIR}/third_party/googletest/googlemock")
  set(googletest_source_dir "${protobuf_SOURCE_DIR}/third_party/googletest/googletest")
  include_directories(
    ${googlemock_source_dir}
    ${googletest_source_dir}
    ${googletest_source_dir}/include
    ${googlemock_source_dir}/include
  )

  add_library(gmock STATIC
    "${googlemock_source_dir}/src/gmock-all.cc"
    "${googletest_source_dir}/src/gtest-all.cc"
  )
  target_link_libraries(gmock ${CMAKE_THREAD_LIBS_INIT})
  add_library(gmock_main STATIC "${googlemock_source_dir}/src/gmock_main.cc")
  target_link_libraries(gmock_main gmock)

  add_library(GTest::gmock ALIAS gmock)
  add_library(GTest::gmock_main ALIAS gmock_main)
endif()

include(${protobuf_SOURCE_DIR}/src/file_lists.cmake)

set(lite_test_protos
  ${protobuf_lite_test_protos_proto_srcs}
)

set(tests_protos
  ${protobuf_test_protos_proto_srcs}
  ${compiler_test_protos_files}
  ${util_test_protos_files}
)

macro(compile_proto_file filename)
  string(REPLACE .proto .pb.cc pb_file ${filename})
  add_custom_command(
    OUTPUT ${pb_file}
    DEPENDS ${protobuf_PROTOC_EXE} ${filename}
    COMMAND ${protobuf_PROTOC_EXE} ${filename}
        --proto_path=${protobuf_SOURCE_DIR}/src
        --cpp_out=${protobuf_SOURCE_DIR}/src
        --experimental_allow_proto3_optional
  )
endmacro(compile_proto_file)

set(lite_test_proto_files)
foreach(proto_file ${lite_test_protos})
  compile_proto_file(${proto_file})
  set(lite_test_proto_files ${lite_test_proto_files} ${pb_file})
endforeach(proto_file)

set(tests_proto_files)
foreach(proto_file ${tests_protos})
  compile_proto_file(${proto_file})
  set(tests_proto_files ${tests_proto_files} ${pb_file})
endforeach(proto_file)

add_library(protobuf-lite-test-common STATIC
  ${lite_test_util_srcs} ${lite_test_proto_files})
target_link_libraries(protobuf-lite-test-common libprotobuf-lite GTest::gmock)

set(common_test_files
  ${lite_test_util_srcs}
  ${test_util_hdrs}
  ${test_util_srcs}
  ${mock_code_generator_srcs}
  ${testing_srcs}
)

add_library(protobuf-test-common STATIC
  ${common_test_files} ${tests_proto_files})
target_link_libraries(protobuf-test-common libprotobuf GTest::gmock)

set(tests_files
  ${protobuf_test_files}
  ${compiler_test_files}
  ${annotation_test_util_srcs}
  ${io_test_files}
  ${util_test_files}
  ${stubs_test_files}
)

if(protobuf_ABSOLUTE_TEST_PLUGIN_PATH)
  add_compile_options(-DGOOGLE_PROTOBUF_TEST_PLUGIN_PATH="$<TARGET_FILE:test_plugin>")
endif()

if(MINGW)
  set_source_files_properties(${tests_files} PROPERTIES COMPILE_FLAGS "-Wno-narrowing")

  # required for tests on MinGW Win64
  if (CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,--stack,16777216")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wa,-mbig-obj")
  endif()

endif()

if(protobuf_TEST_XML_OUTDIR)
  if(NOT "${protobuf_TEST_XML_OUTDIR}" MATCHES "[/\\]$")
    string(APPEND protobuf_TEST_XML_OUTDIR "/")
  endif()
  set(protobuf_GTEST_ARGS "--gtest_output=xml:${protobuf_TEST_XML_OUTDIR}")
else()
  set(protobuf_GTEST_ARGS)
endif()

add_executable(tests ${tests_files})
if (MSVC)
  target_compile_options(tests PRIVATE
    /wd4146 # unary minus operator applied to unsigned type, result still unsigned
  )
endif()
target_link_libraries(tests protobuf-lite-test-common protobuf-test-common libprotoc libprotobuf GTest::gmock_main)

set(test_plugin_files
  ${test_plugin_files}
  ${mock_code_generator_srcs}
  ${testing_srcs}
)

add_executable(test_plugin ${test_plugin_files})
target_link_libraries(test_plugin libprotoc libprotobuf GTest::gmock)

add_executable(lite-test ${protobuf_lite_test_files})
target_link_libraries(lite-test protobuf-lite-test-common libprotobuf-lite GTest::gmock_main)

add_test(NAME lite-test
  COMMAND lite-test ${protobuf_GTEST_ARGS})

add_custom_target(check
  COMMAND tests
  DEPENDS tests test_plugin
  WORKING_DIRECTORY ${protobuf_SOURCE_DIR})

add_test(NAME check
  COMMAND tests ${protobuf_GTEST_ARGS}
  WORKING_DIRECTORY "${protobuf_SOURCE_DIR}")
