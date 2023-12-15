
if(NOT DEFINED ENV{VCPKG_ROOT})
	# Cache location
	if(CMAKE_HOST_WIN32)
		set(PKGXX_CACHE_DIR "$ENV{APPDATA}/pkgxx")
	else()
		set(PKGXX_CACHE_DIR "$ENV{HOME}/.cache/pkgxx")
	endif()

	# load the version and hash from the vcpkg.json file
	file(READ ${CMAKE_SOURCE_DIR}/vcpkg.json VCPKG_JSON)
	string(JSON VCPKG_REPOSITORY ERROR_VARIABLE JSON_ERROR GET ${VCPKG_JSON} "$pkgxx" repository)

	if(JSON_ERROR)
		SET(VCPKG_REPOSITORY "")
	endif()

	string(JSON VCPKG_BASELINE ERROR_VARIABLE JSON_ERROR GET ${VCPKG_JSON} "$pkgxx" baseline)

	if(JSON_ERROR)
		SET(VCPKG_BASELINE "")
	endif()

	# if there is nothing specified, try to load the default-registry
	if("${VCPKG_REPOSITORY}" STREQUAL "" AND "${VCPKG_BASELINE}" STREQUAL "")
		if(EXISTS "${CMAKE_SOURCE_DIR}/vcpkg-configuration.json")
			file(READ "${CMAKE_SOURCE_DIR}/vcpkg-configuration.json" VCPKG_CONFIGURATION_JSON)
			string(JSON VCPKG_REPOSITORY ERROR_VARIABLE JSON_ERROR GET ${VCPKG_CONFIGURATION_JSON} "default-registry" repository)

			if(JSON_ERROR)
				SET(VCPKG_REPOSITORY "")
			endif()

			string(JSON VCPKG_BASELINE ERROR_VARIABLE JSON_ERROR GET ${VCPKG_CONFIGURATION_JSON} "default-registry" baseline)

			if(JSON_ERROR)
				SET(VCPKG_BASELINE "")
			endif()
		endif()
	endif()

	# error out if not set
	if("${VCPKG_REPOSITORY}" STREQUAL "" OR "${VCPKG_BASELINE}" STREQUAL "")
		message(FATAL_ERROR "feiled to load pkgxx configuration")
	endif()

	# set the install dir
	string(REGEX REPLACE "[^a-zA-Z0-9_]+" "_" INSTALL_BASE_NAME "${VCPKG_REPOSITORY}")

	# install dir
	string(SHA256 INSTALL_HASH "v3:${VCPKG_REPOSITORY}:${VCPKG_BASELINE}:")
	set(INSTALL_DIR "${PKGXX_CACHE_DIR}/install/${INSTALL_BASE_NAME}-${VCPKG_BASELINE}")

	# lock file
	set(LOCK_FILE "${PKGXX_CACHE_DIR}/lock/${INSTALL_HASH}.lock")
	file(LOCK "${LOCK_FILE}" GUARD FILE TIMEOUT 300)

	# check the executable
	set(VCPKG_EXECUTABLE "${INSTALL_DIR}/vcpkg")

	if(CMAKE_HOST_WIN32)
		set(VCPKG_EXECUTABLE "${INSTALL_DIR}/vcpkg.exe")
	endif()

	if(NOT EXISTS "${VCPKG_EXECUTABLE}")
		message("## pkgxx: install vcpkg from ${VCPKG_REPOSITORY}")
		message("## pkgxx: installation target: ${INSTALL_DIR}")

		# clean up any invalid install
		file(REMOVE_RECURSE "${INSTALL_DIR}")

		execute_process(
			COMMAND git clone "${VCPKG_REPOSITORY}" "${INSTALL_DIR}"
			RESULT_VARIABLE CLONE_RETURN
			COMMAND_ECHO STDOUT
		)

		# check the clone result
		if(NOT CLONE_RETURN EQUAL 0)
			# clean up
			file(REMOVE_RECURSE "${INSTALL_DIR}")
			file(LOCK "${LOCK_FILE}" RELEASE)
			file(REMOVE "${LOCK_FILE}")
			message(FATAL_ERROR "## pkgxx clone failed")
		endif()

		execute_process(
			COMMAND git -C "${INSTALL_DIR}" reset --hard "${VCPKG_BASELINE}"
			RESULT_VARIABLE RESET_RETURN
			COMMAND_ECHO STDOUT
		)

		# check the reset result
		if(NOT RESET_RETURN EQUAL 0)
			# clean up
			file(REMOVE_RECURSE "${INSTALL_DIR}")
			file(LOCK "${LOCK_FILE}" RELEASE)
			file(REMOVE "${LOCK_FILE}")
			message(FATAL_ERROR "## pkgxx clone failed")
		endif()

		# bootstrap the vcpkg folder
		set(BOOTSTRAP_FILE "${INSTALL_DIR}/bootstrap-vcpkg.sh")

		if(CMAKE_HOST_WIN32)
			set(BOOTSTRAP_FILE "${INSTALL_DIR}/bootstrap-vcpkg.bat")
		endif()

		execute_process(
			COMMAND ${BOOTSTRAP_FILE}
			WORKING_DIRECTORY ${INSTALL_DIR}
			RESULT_VARIABLE BOOTSTRAP_RETURN
			COMMAND_ECHO STDOUT
		)

		# check the bootstrap result
		if(NOT BOOTSTRAP_RETURN EQUAL 0)
			# clean up
			file(REMOVE_RECURSE "${INSTALL_DIR}")
			file(LOCK "${LOCK_FILE}" RELEASE)
			file(REMOVE "${LOCK_FILE}")
			message(FATAL_ERROR "## pkgxx bootstrap failed")
		endif()
	endif()

	# clean up the lock
	file(LOCK "${LOCK_FILE}" RELEASE)
	file(REMOVE "${LOCK_FILE}")

	set(ENV{VCPKG_ROOT} "${INSTALL_DIR}")
endif()

# Set the toolchain file
set(TARGET_TOOLCHAIN "$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake")

# Chain load the existing toolchain
if(DEFINED CMAKE_TOOLCHAIN_FILE AND NOT CMAKE_TOOLCHAIN_FILE STREQUAL TARGET_TOOLCHAIN)
	# don't chainload a toolchain we previously set
	if(NOT PKGXX_SET_TOOLCHAIN STREQUAL CMAKE_TOOLCHAIN_FILE)
		set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE ${CMAKE_TOOLCHAIN_FILE} CACHE STRING "")
	endif()
endif()

if(NOT CMAKE_TOOLCHAIN_FILE STREQUAL TARGET_TOOLCHAIN)
	set(CMAKE_TOOLCHAIN_FILE ${TARGET_TOOLCHAIN} CACHE STRING "" FORCE)
	set(PKGXX_SET_TOOLCHAIN ${TARGET_TOOLCHAIN} CACHE STRING "" FORCE)

	# Total hack, but if we don't change this, then you need to
	# clean your CMakeCache.txt after changing your vcpkg install
	set(Z_VCPKG_ROOT_DIR $ENV{VCPKG_ROOT} CACHE INTERNAL "" FORCE)
endif()
