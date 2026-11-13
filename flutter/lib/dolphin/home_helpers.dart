import 'panel_bridge.dart';

/// Local options (this Windows user's own settings file, never sent to the server or the portal).
/// DD-32: the last ID this app showed, for «شناسه‌ی شما عوض شد».
const kDolphinSeenIdLocal = 'dolphin-seen-id';

/// DD-17: "Y" once the first-run screen was passed with «بعدی».
const kDolphinFirstRunLocal = 'dolphin-first-run-done';

const kIdChangedNotice = 'شناسه‌ی شما عوض شد. شناسه‌ی تازه را به کارشناس دلفین بگویید.';

const kStartHereLabel = 'از اینجا شروع کنید';
const kCopyMyIpLabel = 'کپی IP من';
const kCopyDownloadLabel = 'کپی لینک دانلود';
const kCopyGuideLabel = 'کپی راهنما';

/// The support site's pages the home links to (DD-32). [site] is the brand's site (DolphinBrand.site).
class DolphinLinks {
  final String download;
  final String guide;
  final String help;
  const DolphinLinks._(this.download, this.guide, this.help);

  factory DolphinLinks(String site) {
    final base = site.trim().replaceAll(RegExp(r'/+$'), '');
    return DolphinLinks._('$base/download', '$base/help#connect', '$base/help');
  }
}

/// What the home does with the ID it now shows and the one stored last time.
class IdSeen {
  /// Show «شناسه‌ی شما عوض شد».
  final bool changed;

  /// The value to store, or null to leave the stored one.
  final String? store;
  const IdSeen(this.changed, this.store);
}

/// DD-32. Only a real ID counts (not "Generating …" or ''). The first run stores it and shows nothing; a different ID
/// later shows the notice and becomes the stored one, so the notice belongs to the run that saw the change.
IdSeen idSeen({required String stored, required String current}) {
  if (!panelIdPattern.hasMatch(current)) return const IdSeen(false, null);
  if (stored.isEmpty) return IdSeen(false, current);
  if (stored == current) return const IdSeen(false, null);
  return IdSeen(true, current);
}

/// DD-17: the first-run screen shows until «بعدی» was pressed once on this Windows account.
bool firstRunShown(String flag) => flag != 'Y';
