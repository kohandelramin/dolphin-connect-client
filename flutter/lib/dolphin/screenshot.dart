import 'dart:ffi';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;
import 'package:win32/win32.dart' as win32;

import 'support_upload.dart' show kScreenshotMaxBytes;

/// DD-48: the customer's own screen, captured in this process with GDI (all monitors, the window hidden first by the
/// caller). Windows only; the customer sees the picture and decides before anything is sent. Upstream's capture
/// (libs/scrap) lives in the server process and has no bridge call for the window, so this reads the screen the
/// plain Windows way: no new bridge function and no Rust.

/// The raw capture: top-down BGRA rows.
class RawScreen {
  final int width;
  final int height;
  final Uint8List bgra;
  const RawScreen(this.width, this.height, this.bgra);
}

/// The whole virtual screen (every monitor), in physical pixels (the app is per-monitor DPI aware). Null on failure.
RawScreen? captureScreen() {
  final x = win32.GetSystemMetrics(win32.SYSTEM_METRICS_INDEX.SM_XVIRTUALSCREEN);
  final y = win32.GetSystemMetrics(win32.SYSTEM_METRICS_INDEX.SM_YVIRTUALSCREEN);
  final w = win32.GetSystemMetrics(win32.SYSTEM_METRICS_INDEX.SM_CXVIRTUALSCREEN);
  final h = win32.GetSystemMetrics(win32.SYSTEM_METRICS_INDEX.SM_CYVIRTUALSCREEN);
  if (w <= 0 || h <= 0) return null;
  final screen = win32.GetDC(win32.NULL);
  if (screen == 0) return null;
  final mem = win32.CreateCompatibleDC(screen);
  final bmp = win32.CreateCompatibleBitmap(screen, w, h);
  final info = calloc<win32.BITMAPINFO>();
  final pixels = calloc<Uint8>(w * h * 4);
  try {
    if (mem == 0 || bmp == 0) return null;
    final old = win32.SelectObject(mem, bmp);
    final copied = win32.BitBlt(mem, 0, 0, w, h, screen, x, y, win32.ROP_CODE.SRCCOPY | win32.ROP_CODE.CAPTUREBLT);
    win32.SelectObject(mem, old);
    if (copied == 0) return null;
    info.ref.bmiHeader
      ..biSize = sizeOf<win32.BITMAPINFOHEADER>()
      ..biWidth = w
      ..biHeight = -h // top-down rows
      ..biPlanes = 1
      ..biBitCount = 32
      ..biCompression = win32.BI_COMPRESSION.BI_RGB;
    final lines = win32.GetDIBits(mem, bmp, 0, h, pixels, info, win32.DIB_USAGE.DIB_RGB_COLORS);
    if (lines == 0) return null;
    return RawScreen(w, h, Uint8List.fromList(pixels.asTypedList(w * h * 4)));
  } finally {
    calloc.free(pixels);
    calloc.free(info);
    if (bmp != 0) win32.DeleteObject(bmp);
    if (mem != 0) win32.DeleteDC(mem);
    win32.ReleaseDC(win32.NULL, screen);
  }
}

/// The next width to try when a PNG of [size] bytes is over [max]: area shrinks with the byte count, with a margin.
int nextWidth(int width, int size, int max) {
  final f = math.sqrt(max / size) * 0.9;
  return math.max(320, (width * math.min(f, 0.9)).floor());
}

/// BGRA → PNG under [maxBytes] (the portal's 3 MB): full size first, then smaller until it fits; null if it never
/// does (it always does long before 320 pixels wide). Pure, so tests run it on any platform.
Uint8List? pngUnder(RawScreen raw, {int maxBytes = kScreenshotMaxBytes}) {
  final rgba = Uint8List(raw.bgra.length);
  for (var i = 0; i + 3 < raw.bgra.length; i += 4) {
    rgba[i] = raw.bgra[i + 2];
    rgba[i + 1] = raw.bgra[i + 1];
    rgba[i + 2] = raw.bgra[i];
    rgba[i + 3] = 255; // GDI leaves alpha at 0
  }
  final full = img.Image.fromBytes(width: raw.width, height: raw.height, bytes: rgba.buffer, numChannels: 4)
      .convert(numChannels: 3);
  var image = full;
  for (var i = 0; i < 6; i++) {
    final png = img.encodePng(image, level: 6);
    if (png.length <= maxBytes) return png;
    if (image.width <= 320) return null;
    image = img.copyResize(full, width: nextWidth(image.width, png.length, maxBytes), interpolation: img.Interpolation.average);
  }
  return null;
}

/// Encodes off the window's thread (a 1080p PNG takes a moment in Dart).
Future<Uint8List?> encodeScreen(RawScreen raw) => Isolate.run(() => pngUnder(raw));
