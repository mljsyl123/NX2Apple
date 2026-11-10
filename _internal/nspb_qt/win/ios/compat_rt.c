// Stand-in for the part of Darwin's compiler-rt (libclang_rt.ios.a) that C / Objective-C code
// reaches through @available / __builtin_available.
//
// LLVM's Windows release ships no Darwin runtime libraries, so a target of the form
// arm64-apple-ios* has no libclang_rt.ios.a. When the source uses `@available(iOS 26, *)` the
// compiler emits a call to __isPlatformVersionAtLeast, and without the runtime library the link
// fails with an undefined symbol that says nothing about the real cause.
//
// This repository's own code does not use @available today, so this file is usually not linked.
// build_app.py checks the clang resource directory and only compiles it in when the Darwin
// runtime is genuinely absent — that way a future `@available` in the host does not turn into an
// unexplained link error, and nothing changes on a toolchain that does ship the runtime.
//
// Semantics follow compiler-rt's os_version_check.c on current systems: ask dyld through
// _availability_version_check (libSystem, iOS 15 and later), which every iOS this app can run on
// provides.
#include <stdint.h>

typedef uint32_t dyld_platform_t;
typedef struct { dyld_platform_t platform; uint32_t version; } dyld_build_version_t;

extern _Bool _availability_version_check(uint32_t count, dyld_build_version_t versions[]);

static uint32_t pack(uint32_t major, uint32_t minor, uint32_t sub) {
    return (major << 16) | ((minor & 0xff) << 8) | (sub & 0xff);
}

int32_t __isPlatformVersionAtLeast(uint32_t platform, uint32_t major, uint32_t minor,
                                   uint32_t sub) {
    dyld_build_version_t v = {platform, pack(major, minor, sub)};
    return _availability_version_check(1, &v);
}

// The older entry point, for the platform the binary was built for (2 = iOS).
int32_t __isOSVersionAtLeast(int32_t major, int32_t minor, int32_t sub) {
    return __isPlatformVersionAtLeast(2, (uint32_t)major, (uint32_t)minor, (uint32_t)sub);
}
