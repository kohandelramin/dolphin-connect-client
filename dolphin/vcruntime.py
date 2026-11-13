"""DD-21: a clean Windows 10 without the Visual C++ redistributable must start every Dolphin app.

Upstream already builds with the static runtime: Rust with `+crt-static` (`.cargo/config.toml`) and the Flutter runner
and plugins with `/MT` and `/d2FH4-` (`flutter/windows/CMakeLists.txt`). What upstream does not check is the DLLs that
arrive prebuilt (the engine's `flutter_windows.dll`, `sciter.dll` on x86, the printer adapter). This tool reads the
import tables of every exe and DLL next to the app, copies any VC++ runtime DLL one of them imports from the build
machine's Visual Studio redistributable folder (app-local deployment, which Microsoft allows for these files), and
fails the build when one is still missing. Nothing is copied when nothing imports it.

    python dolphin/vcruntime.py bundle <app folder> --arch x64|x86 [--redist <Microsoft.VC14x.CRT folder>]
    python dolphin/vcruntime.py report <app folder>

Only the folder itself is read, not its subfolders: `drivers\\` holds the printer driver, which Windows loads from the
driver store in its own process, so a DLL next to our exe does not help it.
"""
import argparse
import glob
import os
import pathlib
import re
import shutil
import struct
import subprocess
import sys

# The VC++ 2015-2022 runtime (one ABI, "140"). vcomp140 (OpenMP) lives in its own redist folder.
RUNTIME = re.compile(
    r"^(vcruntime140(_1|_threads)?|msvcp140(_1|_2|_atomic_wait|_codecvt_ids)?|concrt140|vccorlib140|vcomp140)\.dll$",
    re.I,
)
# The Universal CRT is part of Windows 10 and later; on Windows 7 and 8.1 it comes with update KB2999226.
UCRT = re.compile(r"^(api-ms-win-crt-[a-z0-9-]+|ucrtbase)\.dll$", re.I)
MACHINES = {0x8664: "x64", 0x14C: "x86", 0xAA64: "arm64"}


def _u16(b, o):
    return struct.unpack_from("<H", b, o)[0]


def _u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def _cstr(b, o):
    end = b.index(b"\0", o)
    return b[o:end].decode("ascii")


def pe_info(data):
    """(machine, [imported DLL names]) of a PE file, normal and delay-load imports. ValueError when it is not one."""
    if len(data) < 0x40 or data[:2] != b"MZ":
        raise ValueError("not a PE file (no MZ header)")
    pe = _u32(data, 0x3C)
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError("not a PE file (no PE signature)")
    machine = MACHINES.get(_u16(data, pe + 4), hex(_u16(data, pe + 4)))
    sections = _u16(data, pe + 6)
    opt_size = _u16(data, pe + 20)
    opt = pe + 24
    magic = _u16(data, opt)
    if magic == 0x10B:
        image_base, count, dirs = _u32(data, opt + 28), _u32(data, opt + 92), opt + 96
    elif magic == 0x20B:
        image_base, count, dirs = struct.unpack_from("<Q", data, opt + 24)[0], _u32(data, opt + 108), opt + 112
    else:
        raise ValueError(f"unknown optional header magic {magic:#x}")
    table = []
    for i in range(sections):
        s = opt + opt_size + 40 * i
        vsize, va, raw_size, raw_ptr = _u32(data, s + 8), _u32(data, s + 12), _u32(data, s + 16), _u32(data, s + 20)
        table.append((va, max(vsize, raw_size), raw_ptr))

    def offset(rva):
        for va, size, raw_ptr in table:
            if va <= rva < va + size:
                return rva - va + raw_ptr
        raise ValueError(f"RVA {rva:#x} is in no section")

    def directory(i):
        return (_u32(data, dirs + 8 * i), _u32(data, dirs + 8 * i + 4)) if i < count else (0, 0)

    names = []
    rva, size = directory(1)  # IMAGE_DIRECTORY_ENTRY_IMPORT
    if rva and size:
        o = offset(rva)
        while True:
            name_rva = _u32(data, o + 12)
            if name_rva == 0:
                break
            names.append(_cstr(data, offset(name_rva)))
            o += 20
    rva, size = directory(13)  # IMAGE_DIRECTORY_ENTRY_DELAY_IMPORT
    if rva and size:
        o = offset(rva)
        while True:
            attributes, name = _u32(data, o), _u32(data, o + 4)
            if name == 0:
                break
            # Attribute bit 0 clear: an old (VC6) descriptor holding virtual addresses, not RVAs.
            names.append(_cstr(data, offset(name if attributes & 1 else name - image_base)))
            o += 32
    return machine, names


def runtime_imports(names):
    """The VC++ runtime DLLs among imported names, lower-case."""
    return sorted({n.lower() for n in names if RUNTIME.match(n)})


def missing_runtime(imports_by_file, present):
    """VC++ runtime DLLs some file imports and the folder does not have (case-insensitive), sorted."""
    have = {p.lower() for p in present}
    need = set()
    for names in imports_by_file.values():
        need.update(runtime_imports(names))
    return sorted(need - have)


def _version_key(path):
    m = re.search(r"[\\/]MSVC[\\/](\d+(?:\.\d+)*)[\\/]", path, re.I)
    return tuple(int(x) for x in m.group(1).split(".")) if m else ()


def pick_redist(candidates):
    """The newest `...\\VC\\Redist\\MSVC\\<version>\\<arch>\\Microsoft.VC14x.CRT` folder, or None.
    `onecore` and debug (`debug_nonredist`) folders are never used."""
    usable = [c for c in candidates if not re.search(r"onecore|debug_nonredist", c, re.I) and _version_key(c)]
    return max(usable, key=_version_key) if usable else None


def scan(folder):
    """{file name: (machine, imports)} for every .exe and .dll directly in `folder`."""
    out = {}
    for p in sorted(pathlib.Path(folder).iterdir()):
        if p.is_file() and p.suffix.lower() in (".exe", ".dll"):
            out[p.name] = pe_info(p.read_bytes())
    return out


def _find_redist(arch):
    vswhere = os.path.join(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"),
                           "Microsoft Visual Studio", "Installer", "vswhere.exe")
    roots = []
    if os.path.isfile(vswhere):
        out = subprocess.run([vswhere, "-latest", "-products", "*", "-property", "installationPath"],
                             capture_output=True, text=True, check=False).stdout
        roots = [line.strip() for line in out.splitlines() if line.strip()]
    found = []
    for root in roots:
        found += glob.glob(os.path.join(root, "VC", "Redist", "MSVC", "*", arch, "Microsoft.VC14*.CRT"))
    return pick_redist(found)


def report(folder):
    files = scan(folder)
    for name, (machine, imports) in files.items():
        rt = runtime_imports(imports)
        ucrt = sorted({n.lower() for n in imports if UCRT.match(n)})
        print(f"{name} [{machine}]: VC++ runtime {', '.join(rt) or 'none'}; Universal CRT {len(ucrt)} DLL(s)")
    return files


def bundle(folder, arch, redist=None):
    """Copy what is missing until nothing is (a copied DLL may import another one). Returns the copied names."""
    files = report(folder)
    wrong = [n for n, (m, _) in files.items() if m != arch]
    if wrong:
        raise SystemExit(f"vcruntime: not {arch}: {', '.join(wrong)}")
    copied = []
    while True:
        missing = missing_runtime({n: i for n, (_, i) in files.items()}, files)
        if not missing:
            break
        redist = redist or _find_redist(arch)
        if not redist:
            raise SystemExit(f"vcruntime: {', '.join(missing)} needed and no Visual Studio redist folder for {arch} found")
        sources = [pathlib.Path(redist), *pathlib.Path(redist).parent.glob("Microsoft.VC14*.OpenMP")]
        for dll in missing:
            src = next((s / dll for s in sources if (s / dll).is_file()), None)
            if src is None:
                raise SystemExit(f"vcruntime: {dll} is imported but not in {redist}")
            shutil.copy2(src, pathlib.Path(folder) / dll)
            copied.append(dll)
            print(f"vcruntime: copied {dll} from {src.parent}")
        files = scan(folder)
    if not copied:
        print("vcruntime: nothing imports the VC++ runtime; nothing copied")
    if arch == "x86" and any(UCRT.match(n) for _, i in files.values() for n in i):
        print("vcruntime: note: the Universal CRT is needed; Windows 7 and 8.1 get it with update KB2999226")
    return copied


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("bundle")
    b.add_argument("folder")
    b.add_argument("--arch", choices=("x64", "x86"), required=True)
    b.add_argument("--redist")
    r = sub.add_parser("report")
    r.add_argument("folder")
    a = ap.parse_args(argv)
    if a.cmd == "bundle":
        bundle(a.folder, a.arch, a.redist)
    else:
        report(a.folder)
    return 0


if __name__ == "__main__":
    sys.exit(main())
