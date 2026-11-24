"""Compare kernel symbol CRCs that prebuilt modules expect against a kernel build.

Usage:
  python modcrc.py dump  <module.ko>... > crcs.tsv     # "module<TAB>symbol<TAB>crc" per import
  python modcrc.py check <Module.symvers> <crcs.tsv>   # report modules that would fail to load

A module built with CONFIG_MODVERSIONS records the CRC of every kernel symbol it
imports in its __versions section. The kernel refuses to load it if any CRC
differs from the one exported by the running kernel (recorded in Module.symvers).
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

# struct modversion_info { unsigned long crc; char name[MODULE_NAME_LEN]; } on arm64
MODVERSION_ENTRY = 64


def imported_crcs(ko: Path) -> dict[str, int]:
    data = ko.read_bytes()
    if data[:4] != b"\x7fELF" or data[4] != 2:
        raise ValueError(f"{ko.name}: not an ELF64 file")
    shoff, = struct.unpack_from("<Q", data, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", data, 0x3A)

    def section(i: int) -> tuple[int, int, int]:
        name, _type, _flags, _addr, offset, size = struct.unpack_from("<IIQQQQ", data, shoff + i * shentsize)
        return name, offset, size

    _, strtab_off, _ = section(shstrndx)
    for i in range(shnum):
        name_off, offset, size = section(i)
        name = data[strtab_off + name_off : data.index(b"\0", strtab_off + name_off)]
        if name == b"__versions":
            entries = {}
            for pos in range(offset, offset + size, MODVERSION_ENTRY):
                crc, = struct.unpack_from("<Q", data, pos)
                sym = data[pos + 8 : pos + MODVERSION_ENTRY].split(b"\0", 1)[0].decode()
                entries[sym] = crc & 0xFFFFFFFF
            return entries
    return {}


def exported_crcs(symvers: Path) -> dict[str, int]:
    crcs = {}
    for line in symvers.read_text().splitlines():
        crc, sym, *_ = line.split("\t")
        crcs[sym] = int(crc, 16)
    return crcs


def read_tsv(path: Path) -> dict[str, dict[str, int]]:
    modules: dict[str, dict[str, int]] = {}
    for line in path.read_text().splitlines():
        module, sym, crc = line.split("\t")
        modules.setdefault(module, {})[sym] = int(crc, 16)
    return modules


def main(argv: list[str]) -> int:
    match argv:
        case ["dump", *kos]:
            for ko in map(Path, kos):
                for sym, crc in sorted(imported_crcs(ko).items()):
                    print(f"{ko.stem}\t{sym}\t0x{crc:08x}")
            return 0
        case ["check", symvers, tsv]:
            kernel = exported_crcs(Path(symvers))
            modules = read_tsv(Path(tsv))
            broken = 0
            for module, imports in sorted(modules.items()):
                mismatched = [s for s, c in imports.items() if s in kernel and kernel[s] != c]
                missing = [s for s in imports if s not in kernel]
                if mismatched or missing:
                    broken += 1
                    print(f"{module}: {len(mismatched)} crc mismatch, {len(missing)} missing"
                          f"  e.g. {', '.join((mismatched + missing)[:4])}")
            print(f"\n{broken} of {len(modules)} modules would be rejected")
            return 1 if broken else 0
        case _:
            print(__doc__)
            return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
