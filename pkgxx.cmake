
if(NOT DEFINED ENV{VCPKG_ROOT})
	message("## running pkgxx")
	execute_process(
		COMMAND ${CMAKE_CURRENT_LIST_DIR}/pkgxx.sh
		WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
		RESULT_VARIABLE PKGXX_RETURN
	)

	if(NOT PKGXX_RETURN EQUAL 0)
		message(FATAL_ERROR "## pkgxx failed")
	endif()

	include("${CMAKE_SOURCE_DIR}/vcpkg/pkgxx.cmake")
	set(ENV{VCPKG_ROOT} ${CMAKE_SOURCE_DIR}/vcpkg)
endif()

if(DEFINED ENV{VCPKG_ROOT} AND NOT DEFINED CMAKE_TOOLCHAIN_FILE)
  set(CMAKE_TOOLCHAIN_FILE "$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake"
      CACHE STRING "")
endif()

