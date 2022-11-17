
if(NOT DEFINED ENV{VCPKG_ROOT})
	# Cache location
	set(PKGXX_CACHE_DIR "$ENV{HOME}/.cache/pkgxx")

	# load the version and hash from the vcpkg.json file
	file(READ ${CMAKE_SOURCE_DIR}/vcpkg.json VCPKG_JSON)
	string(JSON VCPKG_URL GET ${VCPKG_JSON} "$pkgxx" source)
	string(JSON VCPKG_SHA256 GET ${VCPKG_JSON} "$pkgxx" sha256)

	# install dir
	string(SHA256 INSTALL_HASH "v2:${VCPKG_URL}:${VCPKG_HASH}:")
	set(INSTALL_DIR "${PKGXX_CACHE_DIR}/install/${INSTALL_HASH}")

	# lock file
	set(LOCK_FILE "${PKGXX_CACHE_DIR}/lock/${INSTALL_HASH}.lock")
	file(LOCK "${LOCK_FILE}" GUARD FILE TIMEOUT 300)

	# check the executable
	set(VCPKG_EXECUTABLE "${INSTALL_DIR}/vcpkg")
	if (CMAKE_HOST_WIN32)
		set(VCPKG_EXECUTABLE "${INSTALL_DIR}/vcpkg.exe")
	endif()

	if(NOT EXISTS "${VCPKG_EXECUTABLE}")
		message("## pkgxx: install vcpkg from ${VCPKG_URL}")
		message("## pkgxx: installation target: ${INSTALL_DIR}")

		# clean up any invalid install
		file(REMOVE_RECURSE "${INSTALL_DIR}")

		# download the archive
		set(DOWNLOAD_FILE "${PKGXX_CACHE_DIR}/download/${INSTALL_HASH}")
		file(DOWNLOAD ${VCPKG_URL} ${DOWNLOAD_FILE})

		# check the hash
		file(SHA256 ${DOWNLOAD_FILE} DOWNLOAD_HASH)
		if (NOT DOWNLOAD_HASH STREQUAL VCPKG_SHA256)
			file(REMOVE "${DOWNLOAD_FILE}")
			message(FATAL_ERROR "pkgxx: vcpkg download hash mismatch: ${DOWNLOAD_HASH}!=${VCPKG_SHA256}")
		endif()

		# extract the archive
		set(EXTRACT_DIR "${PKGXX_CACHE_DIR}/extract/${INSTALL_HASH}")
		file(REMOVE_RECURSE "${EXTRACT_DIR}")
		file(ARCHIVE_EXTRACT INPUT "${DOWNLOAD_FILE}" DESTINATION "${EXTRACT_DIR}")
		file(REMOVE "${DOWNLOAD_FILE}")

		# move the archive into place
		file(GLOB ARCHIVE_ROOT "${EXTRACT_DIR}/*")
		file(MAKE_DIRECTORY "${PKGXX_CACHE_DIR}/install")
		file(RENAME "${ARCHIVE_ROOT}" "${INSTALL_DIR}")
		file(REMOVE_RECURSE "${EXTRACT_DIR}")

		# bootstrap the vcpkg folder
		set(BOOTSTRAP_FILE "${INSTALL_DIR}/bootstrap-vcpkg.sh")
		if (CMAKE_HOST_WIN32)
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
	set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE ${CMAKE_TOOLCHAIN_FILE} CACHE STRING "")
endif()

if(NOT CMAKE_TOOLCHAIN_FILE STREQUAL TARGET_TOOLCHAIN)
	set(CMAKE_TOOLCHAIN_FILE ${TARGET_TOOLCHAIN} CACHE STRING "" FORCE)
	# Total hack, but if we don't change this, then you need to
	# clean your CMakeCache.txt after changing your vcpkg install
	set(Z_VCPKG_ROOT_DIR $ENV{VCPKG_ROOT} CACHE INTERNAL "" FORCE)
endif()
