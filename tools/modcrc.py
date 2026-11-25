"""Check whether prebuilt vendor modules would load on a rebuilt kernel.

Usage:
  python modcrc.py dump  <module.ko>... > crcs.tsv     # kernel imports of a full module set
  python modcrc.py check <Module.symvers> <crcs.tsv>   # report modules the kernel would reject

A module built with CONFIG_MODVERSIONS records the CRC of every symbol it imports in
its __versions section, and the kernel refuses to load it if a CRC differs from the
exporter's. `dump` keeps only imports that no module in the set exports itself: those
must come from the kernel image. Symbols shared between vendor modules stay consistent
as long as the modules are shipped together, so they are not checked.
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

# struct modversion_info { unsigned long crc; char name[MODULE_NAME_LEN]; } on arm64
MODVERSION_ENTRY = 64


def sections(ko: Path) -> dict[bytes, bytes]:
    data = ko.read_bytes()
    if data[:4] != b"\x7fELF" or data[4] != 2:
        raise ValueError(f"{ko.name}: not an ELF64 file")
    shoff, = struct.unpack_from("<Q", data, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", data, 0x3A)
    headers = [struct.unpack_from("<IIQQQQ", data, shoff + i * shentsize) for i in range(shnum)]
    strtab = headers[shstrndx][4]
    return {
        data[strtab + name : data.index(b"\0", strtab + name)]: data[offset : offset + size]
        for name, _type, _flags, _addr, offset, size in headers
    }


def imported_crcs(ko: Path) -> dict[str, int]:
    raw = sections(ko).get(b"__versions", b"")
    entries = {}
    for pos in range(0, len(raw), MODVERSION_ENTRY):
        crc, = struct.unpack_from("<Q", raw, pos)
        entries[raw[pos + 8 : pos + MODVERSION_ENTRY].split(b"\0", 1)[0].decode()] = crc & 0xFFFFFFFF
    return entries


def exported_names(ko: Path) -> set[str]:
    return {s.decode() for s in sections(ko).get(b"__ksymtab_strings", b"").split(b"\0") if s}


def kernel_exports(symvers: Path) -> dict[str, int]:
    # Module.symvers line: crc, symbol, exporter ("vmlinux" or a module path), export type
    crcs = {}
    for line in symvers.read_text().splitlines():
        crc, sym, exporter, *_ = line.split("\t")
        if exporter == "vmlinux":
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
            kos = [Path(k) for k in kos]
            provided = set().union(*(exported_names(ko) for ko in kos))
            for ko in kos:
                for sym, crc in sorted(imported_crcs(ko).items()):
                    if sym not in provided:
                        print(f"{ko.stem}\t{sym}\t0x{crc:08x}")
            return 0
        case ["check", symvers, tsv]:
            kernel = kernel_exports(Path(symvers))
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
