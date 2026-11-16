import 'package:flutter/material.dart';

import '../digits.dart';
import '../tech/api.dart';
import 'pc_card.dart' show historyLine;
import 'sections_state.dart';
import 'widgets.dart';

/// Plan 19: «سازمان‌ها» (an admin can add one, OR-6; editing stays on the portal), «تاریخچه» (per organization) and «متن‌های آماده» (copy; «چسباندن» into a
/// session stays in the panel beside the session, DD-50).

String consentLabel(ConsentMode m) => m == ConsentMode.code ? 'با کد یک‌بار مصرف' : 'با «پذیرفتن» مشتری';

class TechOrganizationsView extends StatefulWidget {
  final OrganizationsController orgs;
  final void Function(OrganizationRow org) onShowPcs;
  final void Function(OrganizationRow org) onHistory;

  /// OR-6 «سازمان تازه»: null hides the button (only an admin may make one; the portal refuses anyone else).
  final VoidCallback? onNew;
  const TechOrganizationsView(
      {super.key, required this.orgs, required this.onShowPcs, required this.onHistory, this.onNew});

  @override
  State<TechOrganizationsView> createState() => _TechOrganizationsViewState();
}

class _TechOrganizationsViewState extends State<TechOrganizationsView> {
  late final _search = TextEditingController(text: widget.orgs.query);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.orgs,
      builder: (context, _) {
        final o = widget.orgs;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const TechHeading('سازمان‌ها', size: 15),
              const SizedBox(width: 12),
              SizedBox(
                width: 260,
                child: TextField(
                  key: const ValueKey('orgs-search'),
                  controller: _search,
                  onChanged: o.search,
                  style: TextStyle(fontSize: 13, color: tokensOf(context).text),
                  decoration: techField(context, hint: 'جستجوی نام، شهر یا کد نمایندگی'),
                ),
              ),
              const SizedBox(width: 4),
              TechRefreshButton(key: const ValueKey('orgs-refresh'), busy: o.loading, onPressed: o.load),
              const Spacer(),
              if (widget.onNew != null)
                TechButton('سازمان تازه',
                    key: const ValueKey('orgs-new'), icon: Icons.add, kind: TechButtonKind.primary, onPressed: widget.onNew),
            ]),
            const SizedBox(height: 10),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(flex: 5, child: _list(context, o)),
                if (o.detail != null || o.detailLoading) ...[
                  const SizedBox(width: 10),
                  Expanded(flex: 4, child: _detail(context, o)),
                ],
              ]),
            ),
          ]),
        );
      },
    );
  }

  Widget _list(BuildContext context, OrganizationsController o) {
    final t = tokensOf(context);
    if (o.loading && o.rows.isEmpty) return const TechLoading();
    if (o.rows.isEmpty) {
      return o.error != null
          ? TechEmpty(icon: Icons.error_outline, text: o.error!, action: 'تلاش دوباره', onAction: o.load)
          : const TechEmpty(icon: Icons.apartment_outlined, text: 'سازمانی پیدا نشد.');
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: o.rows.length + (o.hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        if (i >= o.rows.length) return Center(child: TechButton('بیشتر', onPressed: o.loadMore));
        final r = o.rows[i];
        final selected = o.detail?.organization.id == r.id;
        return Material(
          color: selected ? t.surfaceAlt : t.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radius), side: BorderSide(color: t.line)),
          child: InkWell(
            key: ValueKey('org-${r.id}'),
            borderRadius: BorderRadius.circular(t.radius),
            onTap: () => o.open(r.id),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                Container(
                    width: 12, height: 12, decoration: BoxDecoration(color: tileColorFor(r.colorValue), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.name, style: TextStyle(fontWeight: FontWeight.w800, color: t.text)),
                    TechHint([
                      if (r.city != null) r.city!,
                      if (r.dealerCode != null) 'کد ${faDigits(r.dealerCode!)}',
                      consentLabel(r.consentMode),
                      if (!r.active) 'غیرفعال',
                      if (r.training) 'آموزشی',
                    ].join(' · ')),
                  ]),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _detail(BuildContext context, OrganizationsController o) {
    final t = tokensOf(context);
    final d = o.detail;
    if (d == null) return const TechPanel(child: TechLoading());
    final org = d.organization;
    return TechPanel(
      key: const ValueKey('org-detail'),
      child: ListView(children: [
        Row(children: [
          Expanded(child: Text(org.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: t.text))),
          IconButton(tooltip: 'بستن', icon: Icon(Icons.close, size: 18, color: t.textMuted), onPressed: o.closeDetail),
        ]),
        TechHint(consentLabel(org.consentMode)),
        if (d.fixedPassword) TechHint('«اتصال بدون پذیرفتن» روشن است', color: t.success),
        if (org.phones != null) Text(faDigits(org.phones!), style: TextStyle(fontSize: 12.5, color: t.text)),
        if (d.contactName != null) TechHint('رابط: ${d.contactName}'),
        if (d.contractNote != null) ...[const SizedBox(height: 6), TechHint(d.contractNote!)],
        const SizedBox(height: 10),
        Row(children: [
          TechButton('رایانه‌های این سازمان', kind: TechButtonKind.primary, onPressed: () => widget.onShowPcs(org)),
          const SizedBox(width: 6),
          TechButton('تاریخچه', onPressed: () => widget.onHistory(org)),
        ]),
        const SizedBox(height: 12),
        const TechHeading('حساب‌های مشتری'),
        const SizedBox(height: 4),
        if (d.customers.isEmpty) const TechHint('حسابی ندارد.'),
        for (final c in d.customers)
          TechHint([c.name, if (c.phone != null) faDigits(c.phone!), if (!c.active) 'غیرفعال'].join(' · ')),
      ]),
    );
  }
}

class TechHistoryView extends StatelessWidget {
  final HistoryController history;
  final OrganizationsController orgs;
  final DateTime Function() now;
  const TechHistoryView({super.key, required this.history, required this.orgs, this.now = DateTime.now});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([history, orgs]),
      builder: (context, _) {
        final n = now();
        final org = history.organization;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const TechHeading('تاریخچه', size: 15),
              const SizedBox(width: 12),
              PopupMenuButton<OrganizationRow>(
                key: const ValueKey('history-org'),
                tooltip: '',
                color: t.surface,
                onSelected: history.show,
                itemBuilder: (_) => [
                  for (final r in orgs.rows)
                    PopupMenuItem(
                        value: r,
                        child: Directionality(
                            textDirection: TextDirection.rtl, child: Text(r.name, style: TextStyle(color: t.text)))),
                ],
                child: IgnorePointer(child: TechChip(org == null ? 'انتخاب سازمان' : 'سازمان: ${org.name}', dropdown: true, onTap: () {})),
              ),
            ]),
            const SizedBox(height: 10),
            Expanded(
              child: org == null
                  ? const TechEmpty(icon: Icons.history, text: 'یک سازمان را انتخاب کنید تا آخرین تماس‌ها و اتصال‌هایش بیاید.')
                  : history.loading
                      ? const TechLoading()
                      : history.error != null
                          ? TechEmpty(icon: Icons.error_outline, text: history.error!, action: 'تلاش دوباره', onAction: () => history.show(org))
                          : history.rows.isEmpty
                              ? const TechEmpty(icon: Icons.history, text: 'تماسی ثبت نشده است.')
                              : ListView.separated(
                                  itemCount: history.rows.length,
                                  separatorBuilder: (_, __) => Divider(height: 1, color: t.line),
                                  itemBuilder: (context, i) {
                                    final h = history.rows[i];
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Row(children: [
                                        Icon(h is HistoryConnection ? Icons.cast_connected : Icons.inbox_outlined,
                                            size: 16, color: t.textMuted),
                                        const SizedBox(width: 8),
                                        if (h.pcName != null) ...[
                                          SizedBox(
                                              width: 140,
                                              child: Text(h.pcName!,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: t.text))),
                                        ],
                                        Expanded(child: Text(historyLine(h, n), style: TextStyle(fontSize: 12.5, color: t.text))),
                                      ]),
                                    );
                                  },
                                ),
            ),
          ]),
        );
      },
    );
  }
}

class TechSnippetsView extends StatelessWidget {
  final SnippetsController snippets;
  final void Function(Snippet s) onCopy;
  const TechSnippetsView({super.key, required this.snippets, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListenableBuilder(
      listenable: snippets,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const TechHeading('متن‌های آماده', size: 15),
            const Spacer(),
            IconButton(
                tooltip: 'تازه کردن',
                icon: Icon(Icons.refresh, size: 18, color: t.textMuted),
                onPressed: () => snippets.load(refresh: true)),
          ]),
          const TechHint('برای چسباندن در رایانه‌ی مشتری، در پنجره‌ی جلسه پنل کناری را باز کنید و «چسباندن» را بزنید. اینجا فقط کپی می‌شود.'),
          const SizedBox(height: 10),
          Expanded(
            child: snippets.loading && snippets.rows.isEmpty
                ? const TechLoading()
                : snippets.rows.isEmpty
                    ? (snippets.error != null
                        ? TechEmpty(icon: Icons.error_outline, text: snippets.error!, action: 'تلاش دوباره', onAction: snippets.load)
                        : const TechEmpty(icon: Icons.notes, text: 'متن آماده‌ای ثبت نشده است.'))
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: snippets.rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, i) {
                          final s = snippets.rows[i];
                          return TechPanel(
                            key: ValueKey('snippet-${s.id}'),
                            padding: const EdgeInsets.all(10),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(s.title, style: TextStyle(fontWeight: FontWeight.w800, color: t.text)),
                                  const SizedBox(height: 2),
                                  TechHint(s.body, maxLines: 3),
                                ]),
                              ),
                              const SizedBox(width: 8),
                              TechButton('کپی', icon: Icons.copy, onPressed: () => onCopy(s)),
                            ]),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}

/// OR-6 «سازمان تازه» (admin only), as the web form: the organization and, unless «بدون حساب مشتری», its first customer
/// account. The username follows the dealer code until typed; «ساختن رمز» makes a password to read out on the phone.
class TechNewOrganizationView extends StatefulWidget {
  /// Null when it was made (the dialog closes), else the Persian reason shown in the form.
  final Future<String?> Function(NewOrganization org) onCreate;
  final VoidCallback onCancel;

  /// Copies the password to the clipboard.
  final Future<void> Function(String text) onCopy;

  /// Test hook: the «ساختن رمز» source.
  final String Function() makePassword;
  const TechNewOrganizationView(
      {super.key,
      required this.onCreate,
      required this.onCancel,
      required this.onCopy,
      this.makePassword = generateCustomerPassword});

  @override
  State<TechNewOrganizationView> createState() => _TechNewOrganizationViewState();
}

class _TechNewOrganizationViewState extends State<TechNewOrganizationView> {
  final _name = TextEditingController();
  final _dealer = TextEditingController();
  final _accountName = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _usernameTouched = false;
  bool _noAccount = false;
  bool _shown = false;
  bool _copied = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _dealer, _accountName, _username, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final problem = await widget.onCreate(NewOrganization(
      name: _name.text,
      dealerCode: _dealer.text,
      account: _noAccount
          ? null
          : NewCustomerAccount(name: _accountName.text, username: _username.text, password: _password.text),
    ));
    if (!mounted) return;
    if (problem != null) {
      setState(() {
        _busy = false;
        _error = problem;
      });
    }
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 10),
        child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: tokensOf(context).text)),
      );

  Widget _field(BuildContext context, String key, TextEditingController c,
      {bool ltr = false, bool obscure = false, int? maxLength, String? hint, ValueChanged<String>? onChanged}) {
    final t = tokensOf(context);
    return TextField(
      key: ValueKey(key),
      controller: c,
      enabled: !_busy,
      obscureText: obscure,
      maxLength: maxLength,
      autocorrect: false,
      enableSuggestions: false,
      textDirection: ltr ? TextDirection.ltr : null,
      onChanged: onChanged,
      onSubmitted: (_) => _busy ? null : _submit(),
      style: TextStyle(color: t.text, fontSize: 13),
      decoration: techField(context, hint: hint).copyWith(counterText: ''),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      key: const ValueKey('tech-new-org'),
      width: 460,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: t.surface, border: Border.all(color: t.line), borderRadius: BorderRadius.circular(t.radiusLarge)),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('سازمان تازه', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: t.text)),
          const SizedBox(height: 4),
          const TechHint('سازمان و نخستین حساب مشتری‌اش با هم ساخته می‌شوند؛ بقیه‌ی تنظیمات در صفحه‌ی سازمان در پورتال است.'),
          _label(context, 'نام سازمان یا نمایندگی'),
          _field(context, 'neworg-name', _name, maxLength: 200),
          _label(context, 'کد نمایندگی (اختیاری)'),
          _field(context, 'neworg-dealer', _dealer, ltr: true, maxLength: 50, onChanged: (v) {
            if (!_usernameTouched) _username.text = v.trim();
          }),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            decoration: BoxDecoration(border: Border.all(color: t.line), borderRadius: BorderRadius.circular(t.radius)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Checkbox(
                  key: const ValueKey('neworg-no-account'),
                  value: _noAccount,
                  activeColor: t.primary,
                  onChanged: _busy ? null : (v) => setState(() => _noAccount = v ?? false),
                ),
                Expanded(
                  child: Text('بدون حساب مشتری (بعداً در صفحه‌ی سازمان هم می‌شود ساخت)',
                      style: TextStyle(fontSize: 12.5, color: t.text)),
                ),
              ]),
              if (!_noAccount) ...[
                _label(context, 'نام حساب (اختیاری؛ خالی = نام سازمان)'),
                _field(context, 'neworg-account-name', _accountName, maxLength: 100, hint: 'مثلاً آقای محمدی، حسابداری'),
                _label(context, 'نام کاربری'),
                _field(context, 'neworg-username', _username,
                    ltr: true, maxLength: 50, onChanged: (_) => _usernameTouched = true),
                const TechHint('از کد نمایندگی پر می‌شود و قابل تغییر است. حرف لاتین، رقم، نقطه، خط تیره؛ ۳ تا ۵۰ نویسه.'),
                _label(context, 'رمز اولیه (دست‌کم ۱۰ نویسه)'),
                _field(context, 'neworg-password', _password,
                    ltr: true, obscure: !_shown, maxLength: 200, onChanged: (_) => setState(() => _copied = false)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  TechButton(_shown ? 'پنهان کردن' : 'نمایش رمز',
                      key: const ValueKey('neworg-show'),
                      icon: _shown ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      onPressed: () => setState(() => _shown = !_shown)),
                  TechButton('ساختن رمز',
                      key: const ValueKey('neworg-generate'),
                      icon: Icons.auto_fix_high,
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _password.text = widget.makePassword();
                                _shown = true;
                                _copied = false;
                              })),
                  TechButton(_copied ? 'کپی شد' : 'کپی رمز',
                      key: const ValueKey('neworg-copy'),
                      icon: Icons.copy,
                      onPressed: _password.text.isEmpty
                          ? null
                          : () async {
                              await widget.onCopy(_password.text);
                              if (mounted) setState(() => _copied = true);
                            }),
                ]),
                const SizedBox(height: 6),
                const TechHint('رمز را همین حالا یادداشت یا کپی کنید؛ دوباره نشان داده نمی‌شود. مشتری در اولین ورود رمز خودش را انتخاب می‌کند.'),
              ],
            ]),
          ),
          if (_error != null) ...[const SizedBox(height: 10), TechNotice(_error!)],
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TechButton('انصراف', key: const ValueKey('neworg-cancel'), onPressed: _busy ? null : widget.onCancel),
            const SizedBox(width: 8),
            TechButton(_busy ? 'در حال ساختن…' : (_noAccount ? 'ساختن سازمان' : 'ساختن سازمان و حساب'),
                key: const ValueKey('neworg-submit'), kind: TechButtonKind.primary, onPressed: _busy ? null : _submit),
          ]),
        ]),
      ),
    );
  }
}

/// RO-8: the end of a call: reason chips, a note, «پایان تماس» or «بعداً». Shown from the card and after a session
/// window closed on a PC with this technician's open call.
class TechEndOfCallView extends StatefulWidget {
  final String pcName;
  final List<CallReason> reasons;
  final String? initialReasonId;
  final Future<bool> Function(String? reasonId, String? note) onEnd;
  final VoidCallback onLater;
  final String? error;
  const TechEndOfCallView(
      {super.key,
      required this.pcName,
      required this.reasons,
      required this.onEnd,
      required this.onLater,
      this.initialReasonId,
      this.error});

  @override
  State<TechEndOfCallView> createState() => _TechEndOfCallViewState();
}

class _TechEndOfCallViewState extends State<TechEndOfCallView> {
  late String? _reason = widget.initialReasonId;
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      key: const ValueKey('tech-end-of-call'),
      width: 420,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: t.surface, border: Border.all(color: t.line), borderRadius: BorderRadius.circular(t.radiusLarge)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('پایان تماس با «${widget.pcName}»', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: t.text)),
        const SizedBox(height: 4),
        const TechHint('جلسه بسته شد. دلیل تماس را بزنید و اگر لازم است یادداشتی بنویسید؛ یا بعداً از کارت رایانه ببندید.'),
        const SizedBox(height: 12),
        if (widget.reasons.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in widget.reasons)
              TechChip(r.name,
                  key: ValueKey('end-reason-${r.id}'),
                  selected: _reason == r.id,
                  onTap: () => setState(() => _reason = _reason == r.id ? null : r.id)),
          ]),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('end-note'),
          controller: _note,
          minLines: 2,
          maxLines: 4,
          style: TextStyle(color: t.text, fontSize: 13),
          decoration: techField(context, hint: 'یادداشت پایان تماس… (مشتری نمی‌بیند)'),
        ),
        if (widget.error != null) ...[const SizedBox(height: 8), TechNotice(widget.error!)],
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TechButton('بعداً', key: const ValueKey('end-later'), onPressed: _busy ? null : widget.onLater),
          const SizedBox(width: 8),
          TechButton('پایان تماس',
              key: const ValueKey('end-confirm'),
              kind: TechButtonKind.danger,
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      final ok = await widget.onEnd(_reason, _note.text.trim().isEmpty ? null : _note.text.trim());
                      if (mounted && !ok) setState(() => _busy = false);
                    }),
        ]),
      ]),
    );
  }
}
