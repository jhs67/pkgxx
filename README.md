pkgxx
=====

Pkgxx is a cmake script to make it easier to integrate vcpkg into your cmake
based projects. It downloads and bootstraps a standalone vcpkg install
in to your build directory, ready to use with your manifest mode vcpkg
projects.

## Getting started

### Dependencies

You need a project that uses vcpkg packages in manifest mode. 
You can read about manifest mode
[here](https://learn.microsoft.com/en-us/vcpkg/concepts/manifest-mode).

### Installing

Once you have the `vcpkg-configuration.json` file set up, simply
copy the pkgxx.cmake file from this project somewhere in to your project 
directory and then include it early in your cmake file:
```
cmake_minimum_required(VERSION 3.20)

# use pkgxx to install and bootstrap vcpkg
include("path/to/pkgxx.cmake")
```
This will cause pkgxx to install and bootstrap the vcpkg tool,
then load the vcpkg toolchain file to automatically
install the correct version of your vcpkg dependencies.
No need to externally set the VCPKG_ROOT environment variable
or install any other external dependencies -
pkgxx and vcpkg take care of everything! 

If you already have a toolchain file simply set it like normal and
pkgxx will configure vcpkg to chain-load your existing toolchain file.

## Configuration

Usually pkgxx figures out the version of the vcpkg tool to install by
looking at the `default-registry` section of the `vcpkg-configuration.json` file.
It downloads the version file from this source and uses that to pick the
`vcpkg-tools` release to download and bootstrap. It is possible to
override the choice of vcpkg-tool version by specifying the version
in your vcpkg.json file like this:
```
{
    ...,
    "dependencies": [...],
    "$pkgxx": {
        "tool_release": "2025-09-03"
    }
}
```

## License

This project is licensed under the ISC License - see the LICENSE file for details

## Acknowledgments

Thanks to the [vcpkg](https://github.com/microsoft/vcpkg) team for making such a great package system!
