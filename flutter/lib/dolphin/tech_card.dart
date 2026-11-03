import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'theme.dart';
import 'verify.dart';

/// Pushed by the portal (app/src/lib/engine/policy.ts TECH_PHOTO_OPTION, Plan 14 B4): the authorized technician's
/// photo as base64 JPEG, only while that technician may connect to this PC; "-" otherwise.
const kDolphinTechPhotoOption = 'dolphin-tech-photo';

/// The photo's bytes, or null for "-", nothing, bad base64, or anything that is not a small JPEG.
Uint8List? techPhoto(String raw) {
  if (raw.isEmpty || raw == '-') return null;
  try {
    final bytes = base64Decode(raw);
    if (bytes.length < 4 || bytes.length > 16 * 1024 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
    return bytes;
  } catch (_) {
    return null;
  }
}

class TechComing {
  final String name;
  final Uint8List? photo;
  const TechComing(this.name, this.photo);
}

/// Plan 14 (B5): a technician may connect now and nobody is connected yet, so the home says who is coming. Null otherwise.
TechComing? techComing(
    {required String techId,
    required String techName,
    required int until,
    required int nowSeconds,
    required int? connected,
    required String photo}) {
  if (techId.isEmpty || techId == '-' || (connected ?? 0) > 0) return null;
  if (nowSeconds >= until + kDolphinClockSkewSeconds) return null;
  return TechComing(techName == '-' ? '' : techName, techPhoto(photo));
}

/// A round photo, or the person icon when there is none.
class DolphinTechAvatar extends StatelessWidget {
  final Uint8List? photo;
  final double radius;
  const DolphinTechAvatar({super.key, required this.photo, this.radius = 24});

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    return CircleAvatar(
      radius: radius,
      backgroundColor: DolphinColors.azureSoft,
      foregroundImage: photo == null ? null : MemoryImage(photo),
      child: Icon(Icons.person, color: DolphinColors.azure, size: radius),
    );
  }
}

/// «کارشناس دلفین در راه است»: shown above the ID while the portal has authorized a technician for this PC.
class DolphinTechCard extends StatelessWidget {
  final TechComing coming;
  const DolphinTechCard({super.key, required this.coming});

  @override
  Widget build(BuildContext context) {
    final who = coming.name.isEmpty ? 'کارشناس دلفین' : coming.name;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DolphinColors.azureSoft,
        borderRadius: BorderRadius.circular(DolphinRadii.card),
        border: Border.all(color: DolphinColors.lineStrong),
      ),
      child: Row(children: [
        DolphinTechAvatar(photo: coming.photo),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('کارشناس دلفین در راه است', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
            const SizedBox(height: 2),
            Text('$who اجازه‌ی اتصال دارد؛ وقتی پیام اتصال آمد «پذیرفتن» را بزنید.',
                style: const TextStyle(color: DolphinColors.muted, fontSize: 12.5, height: 1.6)),
          ]),
        ),
      ]),
    );
  }
}
