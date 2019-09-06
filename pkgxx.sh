#!/bin/bash

# anchor things to the script location
#root=$(X= cd -- "$(dirname -- "$0")" && pwd -P)
base=$(pwd -P)
vcpkgdir="$base/vcpkg"
vcpkg="$vcpkgdir/vcpkg"

# report an error and exit
error() {
	echo $* >&2
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

# take vcpkg name[variant,list] and parse the name part
parsepackage() {
	local b=$(sed -e 's/\[.*\]//' <<< "$1")
	echo $b
}

# take vcpkg name[variant,list] and parse the variant list
parsevariants() {
	local q=$(sed -e 's/^[^[]*//' -e 's/^\[//' -e 's/]$//' <<< "$1")
	echo $q
}

# take a variant list and clean it up
normalizevariants() {
	# remove 'core' and clean up commas
	local o=$(sed -e 's/core//' -e 's/,+/,/g' -e 's/^,//' -e 's/,$//' <<< "$1")
	# sort and make unique
	local a=$(tr ',' '\n' <<< "$o" | sort -u | tr '\n' ',')
	# remove trailing comma
	echo "${a%?}"
}

# get a good name for a variable based on a prefix and string
varname() {
	local f=$(sed -e 's/[- ]/_/g' <<< "$2")
	echo "$1__$f"
}

# depends "dependent[variant,list]" "dependant"
# declare we need "dependent" installed with the requested variants
# if "dependant" is set then "dependant" depends on "dependent"
depends() {
	# get the base port and add it to the wanted list
	local b=$(parsepackage "$1")
	wanted+=("$b")

	# add the variants for this package
	local q=$(parsevariants "$1")
	local n=$(varname variants "${b}")
	local o=$(normalizevariants "${!n},$q")
	printf -v "${n}" %s "$o"

	# record the dependency
	if [ ! -z "$2" ]; then
		local n=$(varname depends "${2}")
		local o=$(normalizevariants "${!n},$b")
		printf -v "${n}" %s "$o"
	fi
}

# declares a variant as installed
installed() {
	local b=$(parsepackage "$1")
	have+=("$b")

	# add the installed variants for this package
	local q=$(parsevariants "$1")
	local n=$(varname installed "${b}")
	local o=$(normalizevariants "${!n},$q")
	printf -v "${n}" %s "$o"
}

# get the list of variants for a package
wantedvariants() {
	local n=$(varname variants "${1}")
	echo "${!n}"
}

# get the previously installed variant of a package
installedvariants() {
	local n=$(varname installed "${1}")
	echo "${!n}"
}

# get the comma separated list of dependants
wanteddepends() {
	local n=$(varname depends "${1}")
	echo "${!n}"
}

# take a package and optional variant and make a package name
joinpackage() {
	local w=$1
	if [ ! -z "$2" ]; then
		w="$w[core,$2]"
	else
		w="$w[core]"
	fi
	echo "$w"
}

# install all the dependants for a package
installdepends() {
	local d=$(wanteddepends $1)
	if [ ! -z "$d" ]; then
		local a
		IFS=',' read -r -a a <<< "$d"
		for i in "${a[@]}"; do
			installpackage "$i"
		done
	fi
}

# install a package after installing dependants
installpackage() {
	# skip installed packages
	if contains "$1" "${have[@]}"; then
		return
	fi

	#install dependencies first so all the variants are correct
	installdepends "$1"

	local v=$(wantedvariants $1)
	local w=$(joinpackage $1 $v)

	echo \#\# installing ${w}
	"$vcpkg" install "${w}"
	have+=("$1")
}

# read in the configuration file from the root and all submodules
readconfig() {
	# read in the root configuration file
	while read key value; do
		case $key in
		source)
			src="$value"
			;;
		sha256)
			dgst="$value"
			;;
		depends)
			depends "$value"
			;;
		esac
	done < "$base/pkgxx.txt"

	# keep track of input files
	inputs+=("$base/pkgxx.txt")

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
					depends "$value"
				esac
			done < "$base/$path/pkgxx.txt"
			inputs+=("$base/$path/pkgxx.txt")
		done < <(git -C "$base" submodule status --recursive)
	fi

	# clean up the wanted list
	wanted=($(tr ' ' '\n' <<< "${wanted[@]}" | sort -u | tr '\n' ' '))
}

# check if we need to download a new vcpkg
downloadvcpkg() {
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
}

# scan the dependants of the wanted list
scandepends() {
	for i in "${wanted[@]}"; do
		local w=$(joinpackage $i $(wantedvariants $i))
		while read line; do
			local r=$(sed -e 's/.*://' -e 's/ //g' <<< ${line})
			deps=($(tr ',' '\n' <<< "$r" | tr -d ' ' | tr '\n' ' '))
			for dep in "${deps[@]}"; do
				depends "$dep" "$i"
			done
		done < <($vcpkg depend-info "$w")
	done

	# clean up the wanted list
	wanted=($(tr ' ' '\n' <<< "${wanted[@]}" | sort -u | tr '\n' ' '))

	# add default variants for packages without a selected variant
	for i in "${wanted[@]}"; do
		local v=$(wantedvariants $i)
		if [ ! -z "$v" ]; then
			continue
		fi

		local d=$(grep "Default-Features:" $base/vcpkg/ports/$i/CONTROL | sed -e 's/Default-Features://' -e 's/ //')
		if [ -z "$d" ]; then
			continue
		fi

		# set the default variants
		local n=$(varname variants "${i}")
		local o=$(normalizevariants "$d")
		printf -v "${n}" %s "$o"
	done
}

# load the set of packages and variants currently installed
loadinstalled() {
	# load the set of installed packages
	local listed=($($vcpkg list | sed -e "s/:.*$//"))
	if [[ ${listed[0]} == "No" && ${listed[1]} == "packages" ]]; then
		listed=()
	fi

	have=()
	for i in "${listed[@]}"; do
		installed $i
	done

	# clean up the have list
	have=($(tr ' ' '\n' <<< "${have[@]}" | sort -u | tr '\n' ' '))
}

# remove unwanted or mis-variant packages
removeunwanted() {
	for i in "${have[@]}"; do
		local q=$(installedvariants $i)
		local r=$(wantedvariants $i)
		if contains "$i" "${wanted[@]}" && [ "$r" == "$q" ]; then
			continue
		fi
		local w=$(joinpackage "$i" "$q")
		echo \#\# removing ${w}
		"$vcpkg" remove "${w}"
		have=( "${have[@]/$i}" )
	done
}

installmissing() {
	# install wanted but missing packages
	for i in "${wanted[@]}"; do
		installpackage ${i}
	done
}

# tell cmake about input files
writeinputs() {
	echo -n > "$vcpkgdir/pkgxx.cmake"
	for i in "${inputs[@]}"; do
		echo "set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS \"$i\")" >> "$vcpkgdir/pkgxx.cmake"
	done
}

# read the configuration file
echo \#\# pkgxx loading configuration
wanted=()
inputs=()
readconfig

# check if we need to download and setup vcpkg
downloadvcpkg

# find list of needed dependencies
echo \#\# pkgxx scanning dependencies
scandepends

#load the list of installed packages
have=()
loadinstalled

# remove unwanted or mis-variant packages
removeunwanted

# install any missing packages
installmissing

# tell cmake about input files
writeinputs
