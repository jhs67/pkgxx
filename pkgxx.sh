#!/bin/bash

# report an error and exit
log() {
	echo $* >&2
}

error() {
	log $*
	exit 10
}

if [[ "$OSTYPE" == "darwin"* ]]; then
	flockxx() {
		perl -MFcntl=:flock -e'$f=int(shift); open(FH, "<&=", $f); flock(FH, LOCK_EX) or die($!);' $1
	}
else
	flockxx() {
		flock -w 1200 $1
	}
fi;


install_cached() {
	local src="$1"
	local hash="$2"
	local install_hash=$(echo ":$src:$hash:" | openssl dgst -sha256 -binary | xxd -c 32 -p)
	local install_dir="$cache_dir/install/$install_hash"
	mkdir -p "$install_dir"

	(
		# Get an exclusive lock on the install dir
		flockxx 21 || exit 10

		# check if already installed
		[ -x "$install_dir/vcpkg" ] && exit 0

		log \#\# Download vcpkg

		# download to a temporary
		downloadfile=$(mktemp /tmp/pkgxx-download.XXXXXX)

		# make sure temp file is cleaned up if error
		exec 22> "$downloadfile"
		exec 23< "$downloadfile"
		exec 24< "$downloadfile"
		rm -f "$downloadfile"

		curl -L "$src" >&22

		# calculate the file hash
		dgst=$(openssl dgst -sha256 -binary <&23 | xxd -c 32 -p)

		# check the hash
		if [ "$hash" != "$dgst" ]; then
			log vcpkg download hash mismatch: "$hash" != "$dgst"
			exit 10
		fi

		# clean out the install dir
		rm -rf "$install_dir/*"

		# decompress
		tar xzf - -C "$install_dir" --strip-components=1 <&24 >&2 || exit 10

		log \#\# Bootstrap vcpkg

		("$install_dir/bootstrap-vcpkg.sh") >&2 || error "Failed to bootstrap vcpkg"

	) 21<"$install_dir" || {
		rm -rf "$install_dir"
		error "Failed to install vcpkg"
	}

	echo -n "$install_dir"
}

base=$(pwd -P)
cache_dir="$HOME/.cache/pkgxx"
manifest_file="$base/vcpkg.json"
src_url=$(jq -r ".[\"\$pkgxx\"].source" "$manifest_file")
src_sha256=$(jq -r ".[\"\$pkgxx\"].sha256" "$manifest_file")

[ -z "$src_url" -o "$src_url" = "null" ] && error "\$pkgxx.source missing from vcpkg.json"
[ -z "$src_sha256" -o "$src_sha256" = "null" ] && error "\$pkgxx.sha256 missing from vcpkg.json"

install_cached "$src_url" "$src_sha256" || exit 10
