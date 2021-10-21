
if(NOT DEFINED ENV{VCPKG_ROOT})
	message("## running pkgxx")
	execute_process(
		COMMAND ${CMAKE_CURRENT_LIST_DIR}/pkgxx.sh
		WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
		RESULT_VARIABLE PKGXX_RETURN
		OUTPUT_VARIABLE PKGXX_OUTPUT
	)

	if(NOT PKGXX_RETURN EQUAL 0)
		message(FATAL_ERROR "## pkgxx failed")
	endif()

	set(ENV{VCPKG_ROOT} ${PKGXX_OUTPUT})
endif()

# decide if pkgxx should control the tool chain by default
set(DEFAULT_CONTROL TRUE)
if (DEFINED CMAKE_TOOLCHAIN_FILE)
	set(DEFAULT_CONTROL FALSE)
endif()

# set a cache variable to decide if pkgxx controls the tool chain
set(PKGXX_CONTROL_TOOLCHAIN ${DEFAULT_CONTROL} CACHE BOOL "pkgxx controls the tool chain")

# set the toolchain if pkgxx is in control
if(DEFINED ENV{VCPKG_ROOT} AND PKGXX_CONTROL_TOOLCHAIN)
	set(TARGET_TOOLCHAIN "$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake")
	if (NOT CMAKE_TOOLCHAIN_FILE EQUAL TARGET_TOOLCHAIN)
		set(CMAKE_TOOLCHAIN_FILE ${TARGET_TOOLCHAIN} CACHE STRING "" FORCE)
		set(Z_VCPKG_ROOT_DIR $ENV{VCPKG_ROOT} CACHE INTERNAL "" FORCE)
	endif()
endif()
