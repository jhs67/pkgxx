
if(NOT DEFINED ENV{VCPKG_ROOT})
	message("## running pkgxx")
	execute_process(
		COMMAND ${CMAKE_CURRENT_LIST_DIR}/pkgxx.sh
		WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
	)
	set(ENV{VCPKG_ROOT} ${CMAKE_SOURCE_DIR}/vcpkg)
endif()

if(DEFINED ENV{VCPKG_ROOT} AND NOT DEFINED CMAKE_TOOLCHAIN_FILE)
  set(CMAKE_TOOLCHAIN_FILE "$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake"
      CACHE STRING "")
endif()

