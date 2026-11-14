import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart' as win32;

/// Plan 19: small secrets and private data the technician app keeps on disk (the sign-in token, the offline PC list),
/// sealed with Windows DPAPI in the current user's scope: only this Windows account on this PC can open them, and a
/// copied file is useless elsewhere. Nothing here ever logs what it stores.

/// One stored text.
abstract class SecretBox {
  /// The text, or null when nothing is stored or it cannot be opened (another account, a damaged file).
  Future<String?> read();
  Future<void> write(String text);
  Future<void> clear();
}

/// In memory only: tests, and platforms without DPAPI (nothing survives a restart there).
class MemoryBox implements SecretBox {
  String? _text;
  MemoryBox([this._text]);
  @override
  Future<String?> read() async => _text;
  @override
  Future<void> write(String text) async => _text = text;
  @override
  Future<void> clear() async => _text = null;
}

/// Seals bytes for this user. [DpapiSealer] on Windows.
abstract class Sealer {
  Uint8List seal(Uint8List plain);

  /// Null when the blob cannot be opened.
  Uint8List? open(Uint8List sealed);
}

/// DPAPI, user scope (no CRYPTPROTECT_LOCAL_MACHINE), no UI, with an entropy of our own so another program's blob is
/// never mistaken for ours.
class DpapiSealer implements Sealer {
  final List<int> entropy;
  const DpapiSealer([this.entropy = const [100, 99, 45, 116, 101, 99, 104, 45, 118, 49]]); // "dc-tech-v1"

  static const _uiForbidden = 0x1; // CRYPTPROTECT_UI_FORBIDDEN

  @override
  Uint8List seal(Uint8List plain) {
    final out = _run(plain, protect: true);
    if (out == null) throw const FileSystemException('DPAPI refused to protect the data');
    return out;
  }

  @override
  Uint8List? open(Uint8List sealed) => _run(sealed, protect: false);

  Uint8List? _run(Uint8List input, {required bool protect}) {
    if (!Platform.isWindows) return null;
    final inBlob = calloc<win32.CRYPT_INTEGER_BLOB>();
    final entBlob = calloc<win32.CRYPT_INTEGER_BLOB>();
    final outBlob = calloc<win32.CRYPT_INTEGER_BLOB>();
    final inData = calloc<Uint8>(input.isEmpty ? 1 : input.length);
    final entData = calloc<Uint8>(entropy.length);
    try {
      inData.asTypedList(input.length).setAll(0, input);
      entData.asTypedList(entropy.length).setAll(0, entropy);
      inBlob.ref
        ..cbData = input.length
        ..pbData = inData;
      entBlob.ref
        ..cbData = entropy.length
        ..pbData = entData;
      final ok = protect
          ? win32.CryptProtectData(inBlob, nullptr, entBlob, nullptr, nullptr, _uiForbidden, outBlob)
          : win32.CryptUnprotectData(inBlob, nullptr, entBlob, nullptr, nullptr, _uiForbidden, outBlob);
      if (ok == 0 || outBlob.ref.pbData == nullptr) return null;
      final bytes = Uint8List.fromList(outBlob.ref.pbData.asTypedList(outBlob.ref.cbData));
      // Wipe the plain text DPAPI handed back before it is freed.
      if (!protect) outBlob.ref.pbData.asTypedList(outBlob.ref.cbData).fillRange(0, outBlob.ref.cbData, 0);
      win32.LocalFree(outBlob.ref.pbData);
      return bytes;
    } finally {
      inData.asTypedList(input.isEmpty ? 1 : input.length).fillRange(0, input.isEmpty ? 1 : input.length, 0);
      calloc.free(inData);
      calloc.free(entData);
      calloc.free(inBlob);
      calloc.free(entBlob);
      calloc.free(outBlob);
    }
  }
}

/// A sealed file: the text, UTF-8, sealed by [sealer], written atomically (a temp file, then a rename).
class SealedFileBox implements SecretBox {
  final File file;
  final Sealer sealer;
  SealedFileBox(this.file, {this.sealer = const DpapiSealer()});

  @override
  Future<String?> read() async {
    try {
      if (!await file.exists()) return null;
      final plain = sealer.open(await file.readAsBytes());
      if (plain == null) return null;
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String text) async {
    final sealed = sealer.seal(Uint8List.fromList(utf8.encode(text)));
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(sealed, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<void> clear() async {
    for (final f in [file, File('${file.path}.tmp')]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}

/// The folder an app keeps its own files in: [folder] under the user's application-support folder.
Future<Directory> appDataDir(String folder) async {
  final base = await getApplicationSupportDirectory();
  return Directory('${base.path}${Platform.pathSeparator}$folder');
}

/// The folder the technician app keeps its own files in.
Future<Directory> techDataDir() => appDataDir('tech');

/// A DPAPI-sealed file [name] in [folder] on Windows, memory elsewhere. [entropy] keeps one app's blobs apart from
/// another's.
Future<SecretBox> openSealedBox(String folder, String name, {List<int>? entropy}) async {
  if (!Platform.isWindows) return MemoryBox();
  final dir = await appDataDir(folder);
  return SealedFileBox(File('${dir.path}${Platform.pathSeparator}$name'),
      sealer: entropy == null ? const DpapiSealer() : DpapiSealer(entropy));
}

/// The production boxes of the technician app (Windows only).
Future<SecretBox> openBox(String name) => openSealedBox('tech', name);

/// The sealed file of the sign-in (token, expiry, staff).
const kSessionBoxName = 'session.bin';

/// The sealed file of the offline PC list (TD-2).
const kOfflineBoxName = 'pcs.bin';
