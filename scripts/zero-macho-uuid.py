#!/usr/bin/env python3
"""Zero the LC_UUID load command of a thin 64-bit Mach-O binary in place.

Background: ld64's default UUID is supposed to be a deterministic hash of
the linked object files, but in practice (at least with GHC's link line on
macOS aarch64) it varies between builds. Stripping LC_UUID entirely with
-Wl,-no_uuid is not an option — dyld on macOS 14+ refuses to load a
binary with no LC_UUID. Zeroing the 16 UUID bytes leaves the load command
in place (dyld is satisfied) while making the binary reproducible.

Apply this BEFORE codesigning. The ad-hoc codesignature's hash chain
covers the UUID bytes, so re-signing after the zero pass produces a
deterministic signature too.
"""

import struct
import sys

MH_MAGIC_64 = 0xFEEDFACF
LC_UUID = 0x1B
MACHO_HEADER_SIZE = 32  # mach_header_64


def zero_uuid(path: str) -> None:
    with open(path, "rb") as f:
        data = bytearray(f.read())

    if len(data) < MACHO_HEADER_SIZE:
        sys.exit(f"{path}: file too small to be Mach-O")

    magic = struct.unpack("<I", data[:4])[0]
    if magic != MH_MAGIC_64:
        sys.exit(f"{path}: not a 64-bit Mach-O (magic = {magic:#x})")

    ncmds = struct.unpack("<I", data[16:20])[0]

    offset = MACHO_HEADER_SIZE
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack("<II", data[offset : offset + 8])
        if cmd == LC_UUID:
            data[offset + 8 : offset + 24] = b"\x00" * 16
            with open(path, "wb") as f:
                f.write(bytes(data))
            print(f"{path}: zeroed LC_UUID")
            return
        offset += cmdsize

    sys.exit(f"{path}: LC_UUID load command not found")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: zero-macho-uuid.py <path-to-mach-o-binary>")
    zero_uuid(sys.argv[1])
