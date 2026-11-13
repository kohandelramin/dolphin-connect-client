import 'package:flutter/material.dart';

import '../tech/api.dart';
import 'format.dart';
import 'widgets.dart';

/// Plan 19 (T4): the bell's list and the in-app notice. A Windows toast (UN-16's `--dolphin-notify`) rings when the
/// app is not in front; the list and the notice open the PC or the queue.

IconData notificationIcon(NotificationKind k) => switch (k) {
      NotificationKind.callback => Icons.phone_callback_outlined,
      NotificationKind.request => Icons.inbox_outlined,
      NotificationKind.authExpiring => Icons.timer_outlined,
    };

/// The list under the bell, newest first. [unreadBefore]: how many were unread when it opened (shown with ●).
class TechNotificationsPanel extends StatelessWidget {
  final List<AppNotification> items;
  final int unreadBefore;
  final void Function(AppNotification n) onOpen;
  final VoidCallback onClose;
  final DateTime Function() now;
  const TechNotificationsPanel(
      {super.key,
      required this.items,
      required this.onOpen,
      required this.onClose,
      this.unreadBefore = 0,
      this.now = DateTime.now});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final n = now();
    return Material(
      key: const ValueKey('tech-notifications'),
      color: t.surface,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radius), side: BorderSide(color: t.line)),
      child: SizedBox(
        width: 340,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 12, end: 4, top: 4),
              child: Row(children: [
                const Expanded(child: TechHeading('اعلان‌ها')),
                IconButton(
                    tooltip: 'بستن', icon: Icon(Icons.close, size: 18, color: t.textMuted), onPressed: onClose),
              ]),
            ),
            if (items.isEmpty)
              const Padding(padding: EdgeInsets.fromLTRB(12, 4, 12, 16), child: TechHint('اعلان تازه‌ای نیست.'))
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 6),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final it = items[i];
                    final unread = i < unreadBefore;
                    return InkWell(
                      key: ValueKey('notification-${it.id}'),
                      onTap: () => onOpen(it),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: unread ? t.primary : null,
                                  border: Border.all(color: unread ? t.primary : t.lineStrong, width: 1.5)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(notificationIcon(it.kind), size: 17, color: t.textMuted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(it.title,
                                  style: TextStyle(
                                      fontSize: 12.5, color: t.text, fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
                              if (it.body.trim().isNotEmpty) TechHint(it.body, maxLines: 2),
                              TechHint(agoFa(it.at, n)),
                            ]),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// The in-app notice in the window's corner (the design's toast): the mark, the title, the line, «تماس»/«دیدن» and
/// «بعداً».
class TechToastCard extends StatelessWidget {
  final AppNotification item;
  final VoidCallback onOpen;
  final VoidCallback onLater;
  const TechToastCard({super.key, required this.item, required this.onOpen, required this.onLater});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final action = item.kind == NotificationKind.callback && item.deviceId != null ? 'تماس' : 'دیدن';
    return Material(
      key: const ValueKey('tech-toast'),
      color: t.surface,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radius), side: BorderSide(color: t.line)),
      child: SizedBox(
        width: 340,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(t.radiusTiny)),
              child: Icon(notificationIcon(item.kind), size: 18, color: t.onPrimary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title, style: TextStyle(fontWeight: FontWeight.w800, color: t.text)),
                if (item.body.trim().isNotEmpty) TechHint(item.body, maxLines: 3),
                const SizedBox(height: 6),
                Row(children: [
                  TechButton(action, key: const ValueKey('tech-toast-open'), kind: TechButtonKind.primary, onPressed: onOpen),
                  const SizedBox(width: 6),
                  TechButton('بعداً', key: const ValueKey('tech-toast-later'), onPressed: onLater),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
