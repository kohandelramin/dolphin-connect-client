import 'dart:convert';

/// Messages between the technician app and the staff panel inside it (design 2026-10-27, section 4).
/// Pure, so it is unit-tested without the app's native parts.

/// A message from the staff panel (app/src/lib/app-bridge.ts). Anything else is ignored.
class PanelMessage {
  final String type;
  final String id;
  const PanelMessage(this.type, [this.id = '']);
}

final panelIdPattern = RegExp(r'^[A-Za-z0-9_-]{6,32}$');

PanelMessage? parsePanelMessage(dynamic raw) {
  dynamic data = raw;
  if (raw is String) {
    try {
      data = jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
  if (data is! Map) return null;
  final type = data['type'];
  if (type == 'dolphin-hello') return const PanelMessage('dolphin-hello');
  final id = data['id'];
  if (type == 'dolphin-connect' && id is String) {
    final clean = id.replaceAll(' ', '');
    if (panelIdPattern.hasMatch(clean)) return PanelMessage('dolphin-connect', clean);
  }
  return null;
}

/// The panel stays on our portal; any other address is not shown (design 2026-10-27, section 4).
bool isPanelUrl(String url, String portalUrl) =>
    url.isEmpty || url == 'about:blank' || url == portalUrl || url.startsWith('$portalUrl/');
