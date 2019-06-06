#!/bin/bash

# anchor things to the script location
#root=$(X= cd -- "$(dirname -- "$0")" && pwd -P)
base=$(pwd -P)
vcpkgdir="$base/vcpkg"
vcpkg="$vcpkgdir/vcpkg"

# report an error and exit
error() {
    echo $*
    exit 10
}

# execute the vcpkg command
vcpkg() {
    $vcpkgdir/vcpkg $*
}

# test if a value is in a list
contains() {
    local e match="$1"
    shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}


# read the configuration file
echo \#\# pkgxx loading configuration
src=
dgst=
wanted=()
while read key value; do
	case $key in
	source)
		src="$value"
		;;
	sha256)
		dgst="$value"
		;;
	depends)
		wanted+=("$value")
		;;
	esac
done < "$base/pkgxx.txt"

# load dependencies for any submodules
if which git 1>/dev/null 2>/dev/null && git -C "$base" rev-parse --is-inside-work-tree 1>/dev/null  2>/dev/null; then
	while read hash path rest; do
		# skip uninitialized submodules
		if [[ $hash == -* ]]; then
			continue
		fi

		# no pkgxx config for the subnodule
		if [ ! -f "$base/$path/pkgxx.txt" ]; then
			continue;
		fi

		# load depends from the config file
		while read key value; do
			case $key in
			depends)
				wanted+=("$value")
			esac
		done < "$base/$path/pkgxx.txt"
	done < <(git -C "$base" submodule status --recursive)
fi

# get the version downloaded already
oldsrc=
if [ -f "$vcpkgdir/pkgxx-src" ]; then
	oldsrc=$(cat -- "$vcpkgdir/pkgxx-src")
fi

# check if the download needs to happen
if [ "$src" != "$oldsrc" ]; then
	echo \#\# pkgxx download vcpkg

	# remove any old stuff
	rm -rf "$vcpkgdir"

	# download to a temporary
	downloadfile=$(mktemp /tmp/pkgxx-download.XXXXXX)
	curl -L "$src" >"$downloadfile"

	# calculate the file hash
	hash=$(openssl dgst -sha256 -binary "$downloadfile" | xxd -c 32 -p)

	# make sure temp file is cleaned up if error
	exec 3< "$downloadfile"
	rm -f "$downloadfile"

	# check the hash
	if [ "$hash" != "$dgst" ]; then
		echo vcpkg download hash mismatch: "$hash" != "$dgst"
		exit 10
	fi

	# decompress
	mkdir -- "$vcpkgdir" || error "Failed to create vcpkg directory"
	tar xzf - -C "$vcpkgdir" --strip-components=1 <&3 || error "Failed to download vcpkg archive"

	# record the source
	echo -n "$src" > "$vcpkgdir/pkgxx-src"
fi

# bootstrap the vcpkg project
if [ ! -x "$vcpkgdir/vcpkg" ]; then
	echo \#\# Bootstrap vcpkg
    ("$vcpkgdir/bootstrap-vcpkg.sh") || error "Failed to bootstrap vcpkg"
fi

# clean up the wanted list
wanted=($(tr ' ' '\n' <<< "${wanted[@]}" | sort -u | tr '\n' ' '))

# find list of needed dependencies
echo \#\# pkgxx scanning dependencies
declare -a needed
for i in "${wanted[@]}"; do
	b=$(sed -e 's/\[.*\]//' <<< "$i")
	needed+=($b)
done

while read key values; do
	deps=($(tr ',' '\n' <<< "$values" | tr -d ' ' | tr '\n' ' '))
	for dep in "${deps[@]}"; do
		needed+=($dep)
	done
done < <($vcpkg depend-info "${needed[@]}")

# clean up the needed list
needed=($(tr ' ' '\n' <<< "${needed[@]}" | sort -u | tr '\n' ' '))

# load the set of installed packages
have=($($vcpkg list | sed -e "s/:.*$//"))
if [[ ${have[0]} == "No" && ${have[1]} == "packages" ]]; then
    have=()
fi

# remove unwanted packages
for i in "${have[@]}"; do
	b=$(sed -e 's/\[.*\]//' <<< "$i")
    if contains "$b" "${needed[@]}"; then
        continue
    fi
	echo \#\# removing ${i}
    "$vcpkg" remove "${i}"
done

# install wanted but missing packages
for i in "${wanted[@]}"; do
    if contains "$i" "${have[@]}"; then
        continue
    fi
	echo \#\# installing ${i}
    "$vcpkg" install  --recurse "${i}"
done
