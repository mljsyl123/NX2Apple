"""`xcodegen` for Windows: there is none, and this says so clearly.

xcodegen is a Swift program that generates `.xcodeproj` bundles. Nothing equivalent exists on
Windows, and none is needed: an Xcode project only makes sense as input to Xcode, which is
macOS-only. On Windows the app is assembled straight into `DmIOS.app` by `build_app.py`, so the
project-file step is not replaced — it is skipped, and `driver.py` marks the `--prepare-xcode`
option as Mac-only.

This stand-in exists for one reason: `check_prereqs` in the upstream script looks for
`xcodegen` on PATH and refuses to start when it is absent. `driver.py` replaces that check, but
a user who runs the upstream script directly should get an actionable message rather than
"xcodegen not found (brew install xcodegen)" — a Homebrew instruction on Windows.
"""
from __future__ import annotations

import sys


def main(argv: list[str] | None = None) -> int:
    a = list(sys.argv[1:] if argv is not None else (sys.argv[1:] if argv is None else argv))
    if a and a[0] in ('-version', '--version', 'version'):
        print('xcodegen (nspb Windows shim): not used on Windows')
        return 0
    print('xcodegen is not available on Windows and is not needed: the Windows build packs '
          'DmIOS.app directly (no .xcodeproj is generated). If you are running '
          'scripts/build_ipa_from_nsp.py by hand, use the app instead, or pass --platform ios '
          'through the Windows driver (nspb_qt/win/driver.py).', file=sys.stderr)
    return 69


if __name__ == '__main__':
    raise SystemExit(main())
