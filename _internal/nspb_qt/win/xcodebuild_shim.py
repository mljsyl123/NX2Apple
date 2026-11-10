"""`xcodebuild` for Windows: answers the questions the pipeline asks, refuses the rest.

The pipeline uses xcodebuild for exactly two things on the IPA path:

* `check_prereqs` wants `shutil.which('xcodebuild')` to succeed — but `driver.py` replaces that
  check entirely, so this is only for a user who runs the upstream script by hand.
* `toolchain()` records `xcodebuild -version` in the shader cache keys, so the same inputs are
  reused across runs. A stable, honest string keeps the key stable.

Anything that would actually *build* (a bare `xcodebuild`, `-project`, `-scheme`) exits non-zero
with a message pointing at the real path, because there is no Xcode here and pretending
otherwise would produce a confusing failure much later.
"""
from __future__ import annotations

import sys


#: The value recorded in the shader cache keys. It names this shim rather than a fake Xcode
#: version, so a cache built on Windows is never mistaken for one built on a Mac.
VERSION_BANNER = 'xcodebuild (nspb Windows shim; LLVM clang + ld64.lld, no Xcode)'


def main(argv: list[str] | None = None) -> int:
    a = list(sys.argv[1:] if argv is None else argv)
    if not a:
        print(VERSION_BANNER, file=sys.stderr)
        print('there is no Xcode on Windows: the iOS app is compiled with LLVM clang and linked '
              'with ld64.lld (see frontend-qt/README.md, "Windows build")', file=sys.stderr)
        return 69                     # EX_UNAVAILABLE
    if a[0] in ('-version', '--version'):
        print(VERSION_BANNER)
        return 0
    if a[0] in ('-showBuildSettings', '-showsdks', '-list'):
        return 0                      # nothing to list: an empty answer is correct
    if a[0] == '-downloadPlatform':
        print('the iOS SDK is not downloaded through Xcode on Windows: get an iPhoneOS SDK with '
              'the app, or point toolchain.json "ios_sdk" at one', file=sys.stderr)
        return 69
    if a[0] == '-downloadComponent':
        print('the Metal toolchain is not an Xcode component on Windows: install Apple\'s '
              '"Metal Developer Tools for Windows" instead', file=sys.stderr)
        return 69
    print(f'xcodebuild (Windows): cannot build here ({a[0]}); the Windows path packs the IPA '
          'directly with LLVM clang + ld64.lld', file=sys.stderr)
    return 69


if __name__ == '__main__':
    raise SystemExit(main())
