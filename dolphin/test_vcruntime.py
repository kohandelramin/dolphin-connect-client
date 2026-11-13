"""DD-21: the import reader and the copy rules of dolphin/vcruntime.py, on small PE files built here."""
import pathlib
import struct
import tempfile
import unittest

import vcruntime as v


def make_pe(imports=(), delay=(), machine=0x8664, pe32=False, delay_va=False):
    """A minimal PE with one section holding the import and delay-import tables."""
    image_base = 0x400000 if pe32 else 0x140000000
    sect_rva, sect_raw = 0x1000, 0x200
    imp_size = 20 * (len(imports) + 1)
    dly_size = 32 * (len(delay) + 1)
    strings = b""
    name_rvas = []
    for n in list(imports) + list(delay):
        name_rvas.append(sect_rva + imp_size + dly_size + len(strings))
        strings += n.encode() + b"\0"
    body = b""
    for r in name_rvas[:len(imports)]:
        body += struct.pack("<IIIII", 0, 0, 0, r, 0)
    body += b"\0" * 20
    for r in name_rvas[len(imports):]:
        body += struct.pack("<II", 0 if delay_va else 1, r + image_base if delay_va else r) + b"\0" * 24
    body += b"\0" * 32 + strings
    opt_size = 224 if pe32 else 240
    opt = bytearray(opt_size)
    if pe32:
        struct.pack_into("<H", opt, 0, 0x10B)
        struct.pack_into("<I", opt, 28, image_base)
        struct.pack_into("<I", opt, 92, 16)
        dirs = 96
    else:
        struct.pack_into("<H", opt, 0, 0x20B)
        struct.pack_into("<Q", opt, 24, image_base)
        struct.pack_into("<I", opt, 108, 16)
        dirs = 112
    if imports:
        struct.pack_into("<II", opt, dirs + 8, sect_rva, imp_size)
    if delay:
        struct.pack_into("<II", opt, dirs + 8 * 13, sect_rva + imp_size, dly_size)
    coff = struct.pack("<HHIIIHH", machine, 1, 0, 0, 0, opt_size, 0x22)
    section = b".idata\0\0" + struct.pack("<IIIIIIHHI", len(body), sect_rva, len(body), sect_raw, 0, 0, 0, 0, 0)
    head = bytearray(0x40)
    head[:2] = b"MZ"
    struct.pack_into("<I", head, 0x3C, 0x40)
    data = bytes(head) + b"PE\0\0" + coff + bytes(opt) + section
    return data + b"\0" * (sect_raw - len(data)) + body


class PeReaderTest(unittest.TestCase):
    def test_reads_normal_and_delay_imports_of_a_64_bit_file(self):
        machine, names = v.pe_info(make_pe(["KERNEL32.dll", "VCRUNTIME140.dll"], ["MSVCP140.dll"]))
        self.assertEqual(machine, "x64")
        self.assertEqual(names, ["KERNEL32.dll", "VCRUNTIME140.dll", "MSVCP140.dll"])

    def test_reads_a_32_bit_file_and_an_old_virtual_address_delay_descriptor(self):
        machine, names = v.pe_info(make_pe(["USER32.dll"], ["vcruntime140.dll"], machine=0x14C, pe32=True, delay_va=True))
        self.assertEqual(machine, "x86")
        self.assertEqual(names, ["USER32.dll", "vcruntime140.dll"])

    def test_a_file_without_imports_has_none(self):
        self.assertEqual(v.pe_info(make_pe()), ("x64", []))

    def test_refuses_what_is_not_a_pe_file(self):
        with self.assertRaises(ValueError):
            v.pe_info(b"#!/bin/sh\n" + b"\0" * 100)
        bad = bytearray(make_pe(["a.dll"]))
        bad[0x40:0x44] = b"XXXX"
        with self.assertRaises(ValueError):
            v.pe_info(bytes(bad))


class RuntimeRulesTest(unittest.TestCase):
    def test_only_the_vc_runtime_counts_never_windows_or_the_universal_crt(self):
        names = ["KERNEL32.dll", "MSVCP140.dll", "VCRUNTIME140_1.dll", "api-ms-win-crt-runtime-l1-1-0.dll",
                 "ucrtbase.dll", "msvcrt.dll", "vcruntime140d.dll", "MSVCP140_ATOMIC_WAIT.dll", "vcomp140.dll"]
        self.assertEqual(v.runtime_imports(names),
                         ["msvcp140.dll", "msvcp140_atomic_wait.dll", "vcomp140.dll", "vcruntime140_1.dll"])

    def test_missing_is_what_some_file_imports_and_the_folder_lacks(self):
        imports = {"app.exe": ["KERNEL32.dll"], "flutter_windows.dll": ["VCRUNTIME140.dll", "MSVCP140.dll"]}
        self.assertEqual(v.missing_runtime(imports, ["app.exe", "flutter_windows.dll"]),
                         ["msvcp140.dll", "vcruntime140.dll"])
        self.assertEqual(v.missing_runtime(imports, ["app.exe", "flutter_windows.dll", "VCRUNTIME140.DLL", "msvcp140.dll"]), [])
        self.assertEqual(v.missing_runtime({"app.exe": ["KERNEL32.dll"]}, ["app.exe"]), [])

    def test_picks_the_newest_redist_folder_and_never_onecore_or_debug(self):
        base = r"C:\VS\VC\Redist\MSVC"
        picked = v.pick_redist([
            base + r"\14.29.30133\x64\Microsoft.VC142.CRT",
            base + r"\14.40.33807\x64\Microsoft.VC143.CRT",
            base + r"\14.40.33807\onecore\x64\Microsoft.VC143.CRT",
            base + r"\14.44.35112\debug_nonredist\x64\Microsoft.VC143.DebugCRT",
            base + r"\14.38.33135\x64\Microsoft.VC143.CRT",
        ])
        self.assertEqual(picked, base + r"\14.40.33807\x64\Microsoft.VC143.CRT")
        self.assertIsNone(v.pick_redist([]))


class BundleTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        self.app = self.root / "app"
        self.crt = self.root / "VC" / "Redist" / "MSVC" / "14.40.33807" / "x64" / "Microsoft.VC143.CRT"
        self.app.mkdir()
        self.crt.mkdir(parents=True)
        # msvcp140 itself imports vcruntime140 and vcruntime140_1, as the real one does
        (self.crt / "msvcp140.dll").write_bytes(make_pe(["VCRUNTIME140.dll", "VCRUNTIME140_1.dll", "KERNEL32.dll"]))
        (self.crt / "vcruntime140.dll").write_bytes(make_pe(["KERNEL32.dll"]))
        (self.crt / "vcruntime140_1.dll").write_bytes(make_pe(["VCRUNTIME140.dll"]))

    def tearDown(self):
        self.tmp.cleanup()

    def test_copies_what_is_imported_and_what_the_copies_import(self):
        (self.app / "DolphinConnect.exe").write_bytes(make_pe(["KERNEL32.dll"]))
        (self.app / "plugin.dll").write_bytes(make_pe(["MSVCP140.dll"]))
        (self.app / "readme.txt").write_text("not a binary")
        copied = v.bundle(str(self.app), "x64", str(self.crt))
        self.assertEqual(sorted(copied), ["msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"])
        self.assertTrue((self.app / "vcruntime140_1.dll").is_file())

    def test_copies_nothing_when_nothing_imports_it(self):
        (self.app / "DolphinConnect.exe").write_bytes(make_pe(["KERNEL32.dll"]))
        self.assertEqual(v.bundle(str(self.app), "x64", str(self.crt)), [])
        self.assertEqual(sorted(p.name for p in self.app.iterdir()), ["DolphinConnect.exe"])

    def test_subfolders_are_not_read(self):
        (self.app / "DolphinConnect.exe").write_bytes(make_pe(["KERNEL32.dll"]))
        (self.app / "drivers").mkdir()
        (self.app / "drivers" / "filter.dll").write_bytes(make_pe(["MSVCP140.dll"]))
        self.assertEqual(v.bundle(str(self.app), "x64", str(self.crt)), [])

    def test_fails_when_a_needed_dll_is_not_in_the_redist(self):
        (self.app / "a.dll").write_bytes(make_pe(["CONCRT140.dll"]))
        with self.assertRaises(SystemExit):
            v.bundle(str(self.app), "x64", str(self.crt))

    def test_fails_on_a_binary_of_the_other_architecture(self):
        (self.app / "sciter.dll").write_bytes(make_pe(["KERNEL32.dll"], machine=0x14C, pe32=True))
        with self.assertRaises(SystemExit):
            v.bundle(str(self.app), "x64", str(self.crt))


if __name__ == "__main__":
    unittest.main()
