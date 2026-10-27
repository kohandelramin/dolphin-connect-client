import 'dart:convert';

/// Messages between a Dolphin Connect app and the portal page inside it (design 2026-10-27, section 4):
/// the technician app with the staff panel, the customer app with the customer portal.
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

/// The app's answer to the page's hello: its own ID (app/src/lib/app-bridge.ts parseAppMessage).
String idReply(String id) => jsonEncode({'type': 'dolphin-id', 'id': id});

/// The customer's app only answers hello; it never connects out, whatever the page asks.
String? customerReply(PanelMessage m, String myId) =>
    m.type == 'dolphin-hello' && panelIdPattern.hasMatch(myId) ? idReply(myId) : null;
