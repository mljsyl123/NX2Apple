"""Give the IPA's executable the Unix mode bits an iOS install tool expects.

`dm/ios/tools/pack_ipa.py` takes each entry's mode from `os.stat()`, which on a Mac gives
`0o100755` for the app binary and `0o100644` for data files. On Windows `os.stat()` reports
`0o666` for everything — no execute bit at all — so the packed `DmIOS` would look like a plain
data file. Sideloading tools differ in how strictly they check, but a bundle whose main
executable is not executable is not something to ship and hope about.

Two constraints shaped this module:

* **`dm/ios/tools/pack_ipa.py` must not be edited** (it is an upstream file that the daily sync
  overwrites). Its Windows counterpart in the reference implementation added an `--exec`
  argument; ours has no such hook.
* **The IPA can be many gigabytes**, and the executable sits at an arbitrary offset, so a full
  rewrite of the archive would double the disk cost and the time.

So the fix is surgical: locate the central directory, rewrite the mode field of the named
entries in place, and leave every other byte alone. The local file headers carry no mode
(that lives only in the central directory), so one small write per entry is the whole job.
"""
from __future__ import annotations

import os
import stat
import struct
from pathlib import Path

EOCD_SIG = b'PK\x05\x06'
ZIP64_LOCATOR_SIG = b'PK\x06\x07'
ZIP64_EOCD_SIG = b'PK\x06\x06'
CDH_SIG = b'PK\x01\x02'

#: What `stat` reports on a Mac for these files, written the same way Info-ZIP writes them.
MODE_EXEC = stat.S_IFREG | 0o755
MODE_FILE = stat.S_IFREG | 0o644
MODE_DIR = stat.S_IFDIR | 0o755

#: Where the mode lives inside a central-directory header: 16 bytes of signature+version flags,
#: then 10 numeric fields, then the attribute words.
_CD_MODE_OFFSET = 38          # offset of the 4-byte external-attributes field
_CD_MODE_IN_ATTRS = 16        # the mode is in the high 16 bits of external attributes


class IpaModeError(Exception):
    """The archive is not shaped the way this module expects; the message says which part."""


def _find_eocd(f, size: int) -> tuple[int, int, int, int]:
    """(eocd_offset, entry_count, cd_size, cd_offset), following the zip64 records when present."""
    tail_len = min(size, 66_000)   # the comment field is at most 64 KiB
    f.seek(size - tail_len)
    tail = f.read(tail_len)
    i = tail.rfind(EOCD_SIG)
    if i < 0:
        raise IpaModeError('no end-of-central-directory record: not a zip (or a truncated one)')
    eocd = size - tail_len + i
    (count,) = struct.unpack_from('<H', tail, i + 10)
    cd_size, cd_off = struct.unpack_from('<II', tail, i + 12)
    if count == 0xFFFF or cd_size == 0xFFFFFFFF or cd_off == 0xFFFFFFFF:
        # zip64: the real values sit in the zip64 EOCD, reachable through a fixed-size locator
        loc = eocd - 20
        if loc >= 0:
            f.seek(loc)
            rec = f.read(20)
            if len(rec) == 20 and rec[:4] == ZIP64_LOCATOR_SIG:
                z_off, = struct.unpack_from('<Q', rec, 8)
                f.seek(z_off)
                z = f.read(56)
                if len(z) == 56 and z[:4] == ZIP64_EOCD_SIG:
                    count, cd_size, cd_off = struct.unpack_from('<QQQ', z, 32)
    return eocd, count, cd_size, cd_off


def fix(path: os.PathLike | str, executables: list[str], *, dry_run: bool = False) -> str:
    """Rewrite the mode bits of `executables` to 0755 and every other file to 0644.

    Returns a one-line summary for the build log. Idempotent: an archive that is already
    correct is not written to at all.
    """
    path = Path(path)
    size = path.stat().st_size
    if size < 22:
        raise IpaModeError(f'{path} is too small to be a zip')
    exec_set = {e.strip('/') for e in executables}
    wanted: dict[str, int] = {}
    with open(path, 'r+b') as f:
        _eocd, count, cd_size, cd_off = _find_eocd(f, size)
        if count and cd_off + cd_size > size:
            raise IpaModeError(f'the central directory ends past the file ({cd_off + cd_size} > '
                               f'{size}): the archive is truncated')
        f.seek(cd_off)
        cd = f.read(cd_size)
        pos = 0
        seen = 0
        for _ in range(count):
            if pos + 46 > len(cd) or cd[pos:pos + 4] != CDH_SIG:
                raise IpaModeError(f'bad central-directory entry #{seen + 1} at offset {pos}')
            name_len, extra_len, comment_len = struct.unpack_from('<HHH', cd, pos + 28)
            name = cd[pos + 46:pos + 46 + name_len].decode('utf-8', 'surrogateescape')
            (attrs,) = struct.unpack_from('<I', cd, pos + _CD_MODE_OFFSET)
            (created_by,) = struct.unpack_from('<H', cd, pos + 4)
            cur = (attrs >> _CD_MODE_IN_ATTRS) & 0xFFFF
            is_dir = name.endswith('/')
            if is_dir:
                want = MODE_DIR
            elif name in exec_set:
                want = MODE_EXEC
            elif _mode_is_meaningful(cur, created_by):
                # a Mac (or a Unix zip) already wrote a real mode: leave it exactly as it is
                want = cur
            else:
                want = MODE_FILE
            if want != cur:
                wanted[name] = want
            pos += 46 + name_len + extra_len + comment_len
            seen += 1
        if dry_run or not wanted:
            return (f'{len(wanted)} entr{"y" if len(wanted) == 1 else "ies"} would change'
                    if dry_run else 'already correct')
        # rewrite just the attribute word of each affected entry
        for name, mode in wanted.items():
            off = _entry_attr_offset(cd, count, name)
            if off is None:
                continue
            f.seek(cd_off + off)
            attrs, = struct.unpack('<I', f.read(4))
            new = (attrs & 0x0000FFFF) | ((mode & 0xFFFF) << _CD_MODE_IN_ATTRS)
            f.seek(cd_off + off)
            f.write(struct.pack('<I', new))
    missing = exec_set - set(_all_names(path))
    note = f'; missing from the archive: {", ".join(sorted(missing))}' if missing else ''
    return (f'{len(wanted)} entr{"y" if len(wanted) == 1 else "ies"} set to their Unix modes '
            f'({", ".join(sorted(wanted))[:200]}){note}')


def _mode_is_meaningful(mode: int, created_by: int) -> bool:
    """Whether a central-directory mode is a real Unix mode worth keeping.

    Three kinds of value turn up in the wild:

    * a Unix zip (`create_system` 3, a Mac) writes `0o100644` / `0o100755` with the file-type
      bits set — keep it;
    * `pack_ipa.py` on Windows derives the mode from `os.stat()`, which reports `0o666` with no
      type bits — there is nothing to keep, so a data file becomes 0644;
    * Python's `zipfile.writestr` defaults to `0o600` with the type bits set, which would make
      every game file owner-only. That is also not a decision anyone made, so it is repaired.

    A directory entry or an explicitly executable file is handled by the caller before this,
    so this only decides the ordinary-file case.
    """
    if mode == 0 or not mode & 0o777:
        return False
    if created_by >> 8 != 3:
        return False              # not created on Unix: no Unix mode to trust
    if not mode & 0o170000:
        return False              # 0o666-style, straight from os.stat() on Windows
    if mode & 0o777 == 0o600:
        return False              # zipfile's default, not a choice
    return True


def _entry_attr_offset(cd: bytes, count: int, name: str) -> int | None:
    pos = 0
    for _ in range(count):
        if pos + 46 > len(cd) or cd[pos:pos + 4] != CDH_SIG:
            return None
        name_len, extra_len, comment_len = struct.unpack_from('<HHH', cd, pos + 28)
        this = cd[pos + 46:pos + 46 + name_len].decode('utf-8', 'surrogateescape')
        if this == name:
            return pos + _CD_MODE_OFFSET
        pos += 46 + name_len + extra_len + comment_len
    return None


def _all_names(path: Path) -> list[str]:
    size = path.stat().st_size
    out: list[str] = []
    with open(path, 'rb') as f:
        _eocd, count, cd_size, cd_off = _find_eocd(f, size)
        f.seek(cd_off)
        cd = f.read(cd_size)
        pos = 0
        for _ in range(count):
            if pos + 46 > len(cd) or cd[pos:pos + 4] != CDH_SIG:
                break
            name_len, extra_len, comment_len = struct.unpack_from('<HHH', cd, pos + 28)
            out.append(cd[pos + 46:pos + 46 + name_len].decode('utf-8', 'surrogateescape'))
            pos += 46 + name_len + extra_len + comment_len
    return out


def verify(path: os.PathLike | str, executables: list[str]) -> tuple[bool, str]:
    """Check that the named entries carry an execute bit (what the build asserts afterwards)."""
    path = Path(path)
    exec_set = {e.strip('/') for e in executables}
    size = path.stat().st_size
    with open(path, 'rb') as f:
        _eocd, count, cd_size, cd_off = _find_eocd(f, size)
        f.seek(cd_off)
        cd = f.read(cd_size)
        pos = 0
        for _ in range(count):
            if pos + 46 > len(cd) or cd[pos:pos + 4] != CDH_SIG:
                return False, 'central directory is malformed'
            name_len, extra_len, comment_len = struct.unpack_from('<HHH', cd, pos + 28)
            name = cd[pos + 46:pos + 46 + name_len].decode('utf-8', 'surrogateescape')
            if name in exec_set:
                attrs, = struct.unpack_from('<I', cd, pos + _CD_MODE_OFFSET)
                mode = (attrs >> _CD_MODE_IN_ATTRS) & 0xFFFF
                if not mode & 0o111:
                    return False, f'{name} has mode {oct(mode)}, no execute bit'
                return True, f'{name} is {oct(mode)}'
            pos += 46 + name_len + extra_len + comment_len
    return False, f'none of {sorted(exec_set)} is in the archive'
