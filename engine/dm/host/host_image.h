// The Mach-O header of the image that holds the host: the executable in a normal build, the framework's dylib when the host is
// linked as a framework. The linker defines __dso_handle at the start of every image, executable and dylib alike, and
// getsectiondata() takes it as the mach_header_64 *.
#pragma once
#include <mach-o/getsect.h>

extern const struct mach_header_64 __dso_handle;
#define DM_HOST_IMAGE (&__dso_handle)
