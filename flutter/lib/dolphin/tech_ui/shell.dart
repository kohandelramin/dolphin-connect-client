import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand.dart';
import '../demo.dart' show DolphinDemoConfirmView;
import '../tech/actions.dart';
import '../tech/api.dart';
import '../tech/session_store.dart';
import '../tech_theme.dart';
import 'dashboard.dart';
import 'format.dart';
import 'header.dart';
import 'notifications.dart';
import 'pc_card.dart';
import 'requests.dart';
import 'sections.dart';
import 'settings_view.dart';
import 'shell_model.dart';
import 'signin.dart';
import 'widgets.dart';

/// Plan 19 (T1–T7): the native technician window. It replaces the embedded staff panel (technician_home.dart with
/// portal_view.dart): sign-in, then the header, the navigation, the section, the card drawer and the bottom bar. All
/// data comes from the app API through the data layer (tech/); every «اتصال» opens the call on the portal first.
class TechShell extends StatefulWidget {
  final TechShellModel model;

  /// «بررسی نسخه‌ی تازه» in settings › درباره (the app's DolphinUpdateCheckButton); none in tests.
  final Widget? updateButton;

  /// Runs once after the main window first shows signed in (the update popup).
  final void Function(BuildContext context)? onSignedIn;

  /// Test hook: the sections' clock.
  final DateTime Function() now;
  const TechShell({super.key, required this.model, this.updateButton, this.onSignedIn, this.now = DateTime.now});

  @override
  State<TechShell> createState() => _TechShellState();
}

class _TechShellState extends State<TechShell> implements TechPrompts {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _idField = TextEditingController();
  SignInState? _lastState;
  bool _signedInOnce = false;
  String _downloads = '';

  TechShellModel get m => widget.model;
  SessionStore get session => m.services.session;

  @override
  void initState() {
    super.initState();
    m.prompts = this;
    session.addListener(_onSession);
    _onSession();
    m.platform.downloadsDir().then((d) {
      if (mounted) setState(() => _downloads = d.path);
    }, onError: (_) {});
  }

  void _onSession() {
    final s = session.state;
    if (s == _lastState) return;
    final before = _lastState;
    _lastState = s;
    if (s == SignInState.signedIn) {
      m.start();
      if (!_signedInOnce) {
        _signedInOnce = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onSignedIn?.call(context);
        });
      }
    } else if (s == SignInState.expired && before == SignInState.signedIn) {
      m.expired();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    session.removeListener(_onSession);
    if (identical(m.prompts, this)) m.prompts = null;
    _search.dispose();
    _searchFocus.dispose();
    _idField.dispose();
    super.dispose();
  }

  // -- prompts

  @override
  Future<bool> confirmTakeover(String holderName, PcRef pc) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final t = tokensOf(ctx);
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: t.surface,
            title: Text('رایانه در جلسه است', style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
            content: Text(kMsgTakeoverQuestion.replaceFirst('{name}', holderName.isEmpty ? 'کارشناس دیگر' : holderName),
                style: TextStyle(color: t.text, height: 1.7)),
            actions: [
              TechButton('انصراف', kind: TechButtonKind.quiet, onPressed: () => Navigator.of(ctx).pop(false)),
              TechButton('گرفتن جلسه',
                  key: const ValueKey('takeover-yes'), kind: TechButtonKind.primary, onPressed: () => Navigator.of(ctx).pop(true)),
            ],
          ),
        );
      },
    );
    return yes ?? false;
  }

  /// D1 (demo.dart's view, as demo_hooks.dart's showDolphinDemoConfirm shows it).
  @override
  Future<bool?> confirmDemo(PcRef pc) => showDialog<bool>(
        context: context,
        builder: (ctx) {
          var all = false;
          return StatefulBuilder(
            builder: (ctx, setLocal) => Dialog(
              backgroundColor: tokensOf(ctx).surface,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: DolphinDemoConfirmView(
                  peerName: pc.name ?? pc.rustdeskId,
                  allScreens: all,
                  onAllScreens: (v) => setLocal(() => all = v),
                  onStart: () => Navigator.of(ctx).pop(all),
                  onCancel: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
          );
        },
      );

  @override
  Future<void> endOfCall(PcRef pc, OpenCall call) => _showEndOfCall(pc.name ?? pc.rustdeskId, call);

  Future<void> _showEndOfCall(String name, OpenCall call) async {
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: DolphinTechTheme(
            paint: false,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: TechEndOfCallView(
                pcName: name,
                reasons: m.config.callReasons,
                initialReasonId: call.reasonId,
                error: error,
                onLater: () => Navigator.of(ctx).pop(),
                onEnd: (reason, note) async {
                  final problem = await m.endCall(call.requestId, reasonId: reason, note: note);
                  if (problem == null) {
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    return true;
                  }
                  setLocal(() => error = problem);
                  return false;
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -- actions

  PcActions _pcActions() => PcActions(
        open: (pc) => m.openCard(pc.id),
        connect: (pc) => m.connect(PcRef.of(pc)),
        demo: (pc) => m.connect(PcRef.of(pc), demo: true),
        favorite: (pc) => m.dashboard.toggleFavorite(pc),
        wake: (pc) => m.wake(pc.id),
        copyId: (pc) => m.copyId(pc.rustdeskId),
        busy: m.busy,
      );

  Future<void> _connectField({bool demo = false}) async {
    final text = _idField.text;
    await m.connectTyped(text, demo: demo);
  }

  Future<void> _setTheme(ThemeMode mode) async {
    await m.platform.setThemeMode(mode);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => DolphinTechTheme(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: ListenableBuilder(listenable: session, builder: (context, _) => _root(context)),
        ),
      );

  Widget _root(BuildContext context) {
    switch (session.state) {
      case SignInState.unknown:
        return const TechLoading();
      case SignInState.signedOut:
        return TechSignInView(session: session);
      case SignInState.expired:
        return TechSignInView(session: session, expired: true);
      case SignInState.signedIn:
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
              m.go(TechSection.computers);
              _searchFocus.requestFocus();
              _search.selection = TextSelection(baseOffset: 0, extentOffset: _search.text.length);
            },
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (m.bellOpen) {
                m.closeBell();
              } else if (m.cardId != null) {
                m.closeCard();
              }
            },
          },
          child: Focus(
            autofocus: true,
            child: ListenableBuilder(
              listenable: Listenable.merge([
                m,
                m.services.connection,
                m.notifications,
                m.requests,
                m.myCalls,
                m.platform.serverOnline,
                m.platform.sessions,
                m.dashboard,
                m.config,
              ]),
              builder: (context, _) => _main(context),
            ),
          ),
        );
    }
  }

  Widget _main(BuildContext context) {
    final t = tokensOf(context);
    final staff = m.staff;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TechHeader(
        myId: m.myId,
        staffName: staff?.name ?? '',
        search: _search,
        searchFocus: _searchFocus,
        onSearch: (q) {
          if (m.section != TechSection.computers) m.go(TechSection.computers);
          m.dashboard.search(q);
        },
        idField: _idField,
        onConnect: () => _connectField(),
        onDemo: () => _connectField(demo: true),
        busy: m.busy,
        unread: m.notifications.unread,
        onBell: m.toggleBell,
        themeMode: m.platform.themeMode,
        onThemeMode: _setTheme,
        onSettings: () => m.go(TechSection.settings),
        onCopyId: () => m.copyId(m.myId),
        onSignOut: m.signOut,
      ),
      if (m.notice != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TechNotice(m.notice!, ok: m.noticeOk, onClose: m.clearNotice),
        ),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _nav(context),
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: ColoredBox(color: t.background, child: _section(context))),
              if (m.bellOpen)
                Positioned(
                  top: 4,
                  left: 90,
                  child: TechNotificationsPanel(
                    items: m.notifications.items,
                    unreadBefore: m.bellUnread,
                    onOpen: m.openNotification,
                    onClose: m.closeBell,
                    now: widget.now,
                  ),
                ),
              if (m.toast != null)
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: TechToastCard(
                      item: m.toast!, onOpen: () => m.openNotification(m.toast!), onLater: m.dismissToast),
                ),
            ]),
          ),
          if (m.card != null)
            TechPcCard(
              key: ValueKey('card-${m.cardId}'),
              card: m.card!,
              reasons: m.config.callReasons,
              busy: m.busy,
              offline: m.offline,
              onClose: m.closeCard,
              onConnect: (pc) async {
                await m.connect(pc);
                m.card?.load();
              },
              onDemo: (pc) => m.connect(pc, demo: true),
              onEndCall: (pc) {
                final call = m.card?.call;
                if (call != null) _showEndOfCall(pc.name ?? pc.rustdeskId, call);
              },
              onDownload: m.downloadSent,
              onWake: m.wake,
              onCodeOutcome: (o, pc) {
                if (o is Connected) m.noteLaunched(pc);
              },
            ),
        ]),
      ),
      _bottomBar(context),
    ]);
  }

  Widget _section(BuildContext context) {
    switch (m.section) {
      case TechSection.computers:
        return TechDashboard(
          dash: m.dashboard,
          actions: _pcActions(),
          connectId: (id) => m.connectTyped(id),
          offlineReason: m.services.connection.value.reason,
          selectedId: m.cardId,
        );
      case TechSection.requests:
        return TechRequestsView(
          requests: m.requests,
          busy: m.busy,
          now: widget.now,
          onTakeAndCall: m.takeAndCall,
          onCall: (r) => m.connect(PcRef(r.deviceId!, r.rustdeskId!, r.pcName)),
          onOpenPc: (id) {
            m.go(TechSection.computers);
            m.openCard(id);
          },
        );
      case TechSection.myCalls:
        return TechRequestsView(
          requests: m.myCalls,
          mineOnly: true,
          busy: m.busy,
          now: widget.now,
          onTakeAndCall: m.takeAndCall,
          onCall: (r) => m.connect(PcRef(r.deviceId!, r.rustdeskId!, r.pcName)),
          onOpenPc: m.openCard,
        );
      case TechSection.organizations:
        return TechOrganizationsView(
          orgs: m.organizations,
          onShowPcs: (org) {
            m.go(TechSection.computers);
            m.dashboard.setOrganization(org.id);
          },
          onHistory: (org) {
            m.go(TechSection.history);
            m.history.show(org);
          },
        );
      case TechSection.history:
        return TechHistoryView(history: m.history, orgs: m.organizations, now: widget.now);
      case TechSection.snippets:
        return TechSnippetsView(
          snippets: m.snippets,
          onCopy: (s) async {
            await m.platform.copy(s.body);
            m.say('«${s.title}» کپی شد.', ok: true);
          },
        );
      case TechSection.settings:
        return ListenableBuilder(
          listenable: m.dashboard,
          builder: (context, _) => TechSettingsView(
            model: m.settings,
            themeMode: m.platform.themeMode,
            onThemeMode: _setTheme,
            viewMode: m.dashboard.viewMode,
            onViewMode: m.dashboard.setViewMode,
            toasts: m.toastsOn,
            onToasts: m.setToasts,
            downloadsPath: _downloads,
            onOpenDownloads: _downloads.isEmpty ? null : () => m.platform.openFolder(_downloads),
            portalUrl: DolphinBrand.portalUrl,
            serverOnline: m.platform.serverOnline.value,
            portalReachable: !m.offline,
            version: m.platform.version,
            updateButton: widget.updateButton,
          ),
        );
    }
  }

  Widget _nav(BuildContext context) {
    final t = tokensOf(context);
    Widget item(TechSection s, {Widget? trailing}) {
      final on = m.section == s;
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: on ? t.surfaceAlt : Colors.transparent,
          borderRadius: BorderRadius.circular(t.radiusSmall),
          child: InkWell(
            key: ValueKey('nav-${s.name}'),
            borderRadius: BorderRadius.circular(t.radiusSmall),
            onTap: () => m.go(s),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(children: [
                Expanded(
                  child: Text(techSectionTitle(s),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? t.primaryText : t.text)),
                ),
                if (trailing != null) trailing,
              ]),
            ),
          ),
        ),
      );
    }

    Widget count(int n) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(color: t.background, borderRadius: BorderRadius.circular(99)),
          child: Text(idFaNum(n), style: TextStyle(fontSize: 11, color: t.text)),
        );

    final pcs = m.dashboard.offline ? m.dashboard.items.length : m.dashboard.counts.matching;
    return Container(
      width: 176,
      decoration: BoxDecoration(color: t.surface, border: BorderDirectional(end: BorderSide(color: t.line))),
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        item(TechSection.computers, trailing: count(pcs)),
        item(TechSection.requests, trailing: m.requests.queueCount > 0 ? TechBadge(m.requests.queueCount) : null),
        item(TechSection.myCalls, trailing: m.myCalls.mineCount > 0 ? count(m.myCalls.mineCount) : null),
        item(TechSection.organizations),
        item(TechSection.history),
        item(TechSection.snippets),
        const Spacer(),
        item(TechSection.settings),
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('nav-portal'),
            borderRadius: BorderRadius.circular(t.radiusSmall),
            onTap: () => m.platform.openUrl('${DolphinBrand.portalUrl}/staff'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(children: [
                Expanded(
                    child: Text('باز کردن پورتال', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.text))),
                Icon(Icons.open_in_new, size: 15, color: t.textMuted),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _bottomBar(BuildContext context) => TechBottomBar(
        sessions: [
          for (final s in m.platform.sessions.open) (s.rustdeskId, m.sessionName(s.rustdeskId), s.since),
        ],
        serverOnline: m.platform.serverOnline.value,
        portalOffline: m.offline,
        onFocus: (id) => m.platform.focusSession(id),
        now: widget.now,
      );
}

/// The bottom bar: open sessions (name · time · state; a click brings that window up, TD-9) and the server's state.
class TechBottomBar extends StatefulWidget {
  final List<(String, String, DateTime)> sessions;
  final bool? serverOnline;
  final bool portalOffline;
  final void Function(String rustdeskId) onFocus;
  final DateTime Function() now;
  const TechBottomBar(
      {super.key,
      required this.sessions,
      required this.serverOnline,
      required this.onFocus,
      this.portalOffline = false,
      this.now = DateTime.now});

  @override
  State<TechBottomBar> createState() => _TechBottomBarState();
}

class _TechBottomBarState extends State<TechBottomBar> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(TechBottomBar old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.sessions.isEmpty) {
      _tick?.cancel();
      _tick = null;
    } else {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final now = widget.now();
    final server = widget.serverOnline;
    return Container(
      key: const ValueKey('tech-bottom-bar'),
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: t.surface, border: Border(top: BorderSide(color: t.line))),
      child: Row(children: [
        const TechHint('جلسه‌های باز:'),
        const SizedBox(width: 6),
        Expanded(
          child: widget.sessions.isEmpty
              ? const TechHint('جلسه‌ای باز نیست')
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final (id, name, since) in widget.sessions)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: TechChip('$name · ${elapsedFa(now.difference(since))} · وصل',
                            key: ValueKey('session-$id'), selected: false, onTap: () => widget.onFocus(id)),
                      ),
                  ]),
                ),
        ),
        if (widget.portalOffline) ...[
          TechHint('پورتال: در دسترس نیست', color: t.warning),
          const SizedBox(width: 12),
        ],
        TechHint(
          server == null ? 'سرور دلفین: …' : (server ? 'سرور دلفین: وصل' : 'سرور دلفین: وصل نیست'),
          color: server == false ? t.warning : null,
        ),
        const SizedBox(width: 6),
        TechDot(server == true ? PcState.online : (server == false ? PcState.offline : PcState.unknown), size: 8),
      ]),
    );
  }
}
