import 'package:flutter/foundation.dart';

/// Plan 19 (C2): what the customer lets the technician do, chosen in the accept prompt and changed in the session
/// window. Two ready-made profiles (idea from AnyDesk): «کامل» and «فقط تماشا». Sound is off in both by default
/// (DD-31, owner 2026-11-13); the customer turns it on with its own switch. Pure, so the rules are tested alone
/// (test/dolphin/access_profile_test.dart).
///
/// The technician cannot change any of this from his side: upstream's `allow-remote-cm-modification` is pushed "N" by
/// the portal (dolphin/settings.json), which wraps the whole connection window in upstream's remote-input block
/// (server_page.dart `buildRemoteBlock`), and every press in our window is also checked against the technician's last
/// click (connection.dart, upstream's `checkClickTime`).
@immutable
class DolphinGrant {
  final bool keyboard;
  final bool clipboard;
  final bool file;
  final bool audio;
  const DolphinGrant({required this.keyboard, required this.clipboard, required this.file, required this.audio});

  /// «کامل»: mouse and keyboard, clipboard and file transfer (ADR-0012: on by default); sound stays off (DD-31).
  static const full = DolphinGrant(keyboard: true, clipboard: true, file: true, audio: false);

  /// «فقط تماشا»: the technician sees the screen and nothing else.
  static const viewOnly = DolphinGrant(keyboard: false, clipboard: false, file: false, audio: false);

  /// The prompt opens on «کامل».
  static const initial = full;

  DolphinGrant copyWith({bool? keyboard, bool? clipboard, bool? file, bool? audio}) => DolphinGrant(
      keyboard: keyboard ?? this.keyboard,
      clipboard: clipboard ?? this.clipboard,
      file: file ?? this.file,
      audio: audio ?? this.audio);

  /// One switch by its `bind.cmSwitchPermission` name.
  bool of(String permission) => switch (permission) {
        'keyboard' => keyboard,
        'clipboard' => clipboard,
        'file' => file,
        'audio' => audio,
        _ => throw ArgumentError.value(permission, 'permission'),
      };

  DolphinGrant withPermission(String permission, bool on) => switch (permission) {
        'keyboard' => copyWith(keyboard: on),
        'clipboard' => copyWith(clipboard: on),
        'file' => copyWith(file: on),
        'audio' => copyWith(audio: on),
        _ => throw ArgumentError.value(permission, 'permission'),
      };

  /// What is actually granted when the organization does not offer sound (`remote-sound` hidden): never sound.
  DolphinGrant offered({required bool sound}) => sound ? this : copyWith(audio: false);

  @override
  bool operator ==(Object other) =>
      other is DolphinGrant &&
      other.keyboard == keyboard &&
      other.clipboard == clipboard &&
      other.file == file &&
      other.audio == audio;

  @override
  int get hashCode => Object.hash(keyboard, clipboard, file, audio);

  @override
  String toString() => 'DolphinGrant(keyboard: $keyboard, clipboard: $clipboard, file: $file, audio: $audio)';
}

enum DolphinProfile { full, viewOnly, custom }

const kProfileFullLabel = 'کامل';
const kProfileViewOnlyLabel = 'فقط تماشا';

/// The profile a grant matches; switching one key by hand makes it [DolphinProfile.custom] (neither segment lit).
/// Sound does not decide the profile: it is its own choice in both.
DolphinProfile profileOf(DolphinGrant g) {
  final rest = g.copyWith(audio: false);
  if (rest == DolphinGrant.full) return DolphinProfile.full;
  if (rest == DolphinGrant.viewOnly && !g.audio) return DolphinProfile.viewOnly;
  return DolphinProfile.custom;
}

/// Pressing a segment: «فقط تماشا» turns everything off, sound too; «کامل» turns the three on and keeps sound off.
DolphinGrant grantFor(DolphinProfile p, DolphinGrant current) => switch (p) {
      DolphinProfile.full => DolphinGrant.full,
      DolphinProfile.viewOnly => DolphinGrant.viewOnly,
      DolphinProfile.custom => current,
    };

/// The switches the customer reads (C2 and C3), by `bind.cmSwitchPermission` name. Sound shows only when the
/// organization offers it.
const kGrantLabels = [
  ('keyboard', 'ماوس و صفحه‌کلید'),
  ('clipboard', 'کلیپ‌بورد'),
  ('file', 'انتقال فایل'),
  ('audio', 'صدای رایانه'),
];

List<(String, String)> grantLabels({required bool sound}) => [
      for (final l in kGrantLabels)
        if (sound || l.$1 != 'audio') l,
    ];

/// Under the switches in the prompt (design C2; idea from DorsanDesk).
const kGrantOnlyYouLine = 'این کلیدها را فقط شما با ماوس خودتان عوض می‌کنید، نه کارشناس.';

/// Upstream's own test for a press the technician made: the connection records the time of every remote click
/// (src/server/connection.rs CLICK_TIME) and a press in the connection window within this many milliseconds of it is
/// his, not the customer's (server_page.dart `checkClickTime`).
const kDolphinRemoteClickMs = 120;

/// True when a press at [pressedMs] was the customer's own: the technician's last click was longer ago than
/// [kDolphinRemoteClickMs] (or never, 0).
bool clickIsLocal({required int pressedMs, required int remoteClickMs}) => pressedMs - remoteClickMs > kDolphinRemoteClickMs;
