import 'package:flutter/material.dart';

import '../brand.dart';
import '../signin_expired.dart' show kSignInExpiredTitle;
import '../tech/session_store.dart';
import 'widgets.dart';

/// Plan 19: the technician app's sign-in (ADR-0008: username and password only, no second step). The same form after
/// the portal said the sign-in is over (8 h, revoked, deactivated): «ورود منقضی شد» on top (the DD-15 wording). The
/// password is never kept: it goes to the session store once and the field is cleared.
const kSignInTitle = 'ورود کارشناس';
const kSignInLead = 'با نام کاربری و رمز عبوری که مدیر دلفین به شما داده است وارد شوید.';
const kSignInExpiredLead = 'زمان ورود شما تمام شده است؛ دوباره وارد شوید. جلسه‌های باز بسته نشده‌اند.';
const kSignInButton = 'ورود';
const kUsernameLabel = 'نام کاربری';
const kPasswordLabel = 'رمز عبور';

class TechSignInView extends StatefulWidget {
  final SessionStore session;

  /// True after the portal ended the sign-in (shows «ورود منقضی شد»).
  final bool expired;
  const TechSignInView({super.key, required this.session, this.expired = false});

  @override
  State<TechSignInView> createState() => _TechSignInViewState();
}

class _TechSignInViewState extends State<TechSignInView> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _passFocus = FocusNode();
  bool _show = false;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await widget.session.signIn(_user.text, _pass.text);
    if (!mounted) return;
    _pass.clear();
    if (!ok) _passFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final busy = widget.session.busy;
        final error = widget.session.error;
        return ColoredBox(
          color: t.background,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: t.surface,
                      border: Border.all(color: t.line),
                      borderRadius: BorderRadius.circular(t.radiusLarge)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
                    child: AutofillGroup(
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Icon(Icons.support_agent, color: t.primaryText, size: 26),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(DolphinBrand.technicianNameFa,
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: t.primaryText)),
                          ),
                        ]),
                        const SizedBox(height: 16),
                        if (widget.expired) ...[
                          Container(
                            key: const ValueKey('tech-signin-expired'),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: t.warningSoft, borderRadius: BorderRadius.circular(t.radiusSmall)),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(Icons.lock_clock_outlined, size: 20, color: t.warning),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(kSignInExpiredTitle,
                                      style: TextStyle(fontWeight: FontWeight.w800, color: t.warning)),
                                  const SizedBox(height: 2),
                                  Text(kSignInExpiredLead, style: TextStyle(fontSize: 12.5, height: 1.7, color: t.warning)),
                                ]),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 14),
                        ],
                        Text(kSignInTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: t.text)),
                        const SizedBox(height: 4),
                        Text(kSignInLead, style: TextStyle(fontSize: 12.5, height: 1.7, color: t.textMuted)),
                        const SizedBox(height: 16),
                        Text(kUsernameLabel, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: t.text)),
                        const SizedBox(height: 4),
                        TextField(
                          key: const ValueKey('tech-signin-user'),
                          controller: _user,
                          enabled: !busy,
                          autofocus: true,
                          textDirection: TextDirection.ltr,
                          autofillHints: const [AutofillHints.username],
                          style: TextStyle(color: t.text),
                          decoration: techField(context),
                          onSubmitted: (_) => _passFocus.requestFocus(),
                        ),
                        const SizedBox(height: 12),
                        Text(kPasswordLabel, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: t.text)),
                        const SizedBox(height: 4),
                        TextField(
                          key: const ValueKey('tech-signin-pass'),
                          controller: _pass,
                          focusNode: _passFocus,
                          enabled: !busy,
                          obscureText: !_show,
                          enableSuggestions: false,
                          autocorrect: false,
                          textDirection: TextDirection.ltr,
                          autofillHints: const [AutofillHints.password],
                          style: TextStyle(color: t.text),
                          decoration: techField(context,
                              suffix: IconButton(
                                tooltip: _show ? 'پنهان کردن رمز' : 'نمایش رمز',
                                icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                    size: 18, color: t.textMuted),
                                onPressed: () => setState(() => _show = !_show),
                              )),
                          onSubmitted: (_) => _submit(),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 10),
                          Text(error,
                              key: const ValueKey('tech-signin-error'),
                              style: TextStyle(fontSize: 12.5, height: 1.7, color: t.danger)),
                        ],
                        const SizedBox(height: 16),
                        FilledButton(
                          key: const ValueKey('tech-signin-submit'),
                          style: FilledButton.styleFrom(
                              backgroundColor: t.primary,
                              foregroundColor: t.onPrimary,
                              disabledBackgroundColor: t.surfaceAlt,
                              disabledForegroundColor: t.textMuted),
                          onPressed: busy ? null : _submit,
                          child: busy
                              ? SizedBox(
                                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: t.onPrimary))
                              : const Text(kSignInButton),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
