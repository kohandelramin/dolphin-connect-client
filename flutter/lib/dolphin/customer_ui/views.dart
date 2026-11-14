import 'package:flutter/material.dart';

import '../customer_api/api.dart';
import '../digits.dart';
import '../theme.dart';
import 'format.dart';
import 'widgets.dart';

/// Plan 19 C4 (approved 2026-11-14): the customer app's own «درخواست‌ها و پیام‌ها», screens C4.1–C4.5. Pure: everything
/// comes in as values and callbacks; customer_requests.dart holds the state and talks to the portal. Every screen draws
/// with [DolphinLight], so it follows the customer's light or dark (C5).

const kRequestsTitle = 'درخواست‌ها و پیام‌ها';

// C4.1
const kSignInHeading = 'ورود به پشتیبانی دلفین';
const kSignInLead = 'نام کاربری و رمز را دلفین به شما داده است. ثبت‌نام آزاد نیست.';
const kSignInExpiredText = 'ورود شما تمام شده است؛ دوباره وارد شوید.';
const kUsernameLabel = 'نام کاربری';
const kPasswordLabel = 'رمز';
const kSignInButton = 'ورود';

/// «نام کاربری ندارید؟ با ۰۲۱-۴۴۲۸۰۵۰۵ تماس بگیرید.»
String noAccountLine(String phone) =>
    phone.trim().isEmpty ? 'نام کاربری ندارید؟ با پشتیبانی دلفین تماس بگیرید.' : 'نام کاربری ندارید؟ با ${faDigits(phone.trim())} تماس بگیرید.';

// C4.2
const kMyRequests = 'درخواست‌های من';
const kNewRequest = 'درخواست تازه';
const kOpenTab = 'باز';
const kClosedTab = 'بسته‌شده';
const kAccountMenu = 'حساب';
const kChangePasswordItem = 'تغییر رمز';
const kSignOutItem = 'خروج';
const kNoOpen = 'درخواست بازی ندارید. برای کار تازه «درخواست تازه» را بزنید.';
const kNoClosed = 'هنوز درخواست بسته‌شده‌ای ندارید.';
const kUnreadDotLabel = 'پیام تازه از کارشناس';
const kRetry = 'تلاش دوباره';

// C4.3
const kProductLabel = 'نرم‌افزار';
const kProductUnknown = 'نمی‌دانم / دیگر';
const kSubjectLabel = 'موضوع';
const kDescriptionLabel = 'توضیح';
const kScreenshotSwitch = 'عکس صفحه را هم بفرست';
const kUrgentSwitch = 'فوری است؛ کار متوقف شده';
const kSendButton = 'فرستادن';
const kCancelButton = 'انصراف';
const kRequestFieldsError = 'موضوع (دست‌کم ۳ نویسه) و توضیح (دست‌کم ۵ نویسه) را بنویسید.';

/// «شناسه‌ی این رایانه (۱۲۳ ۴۵۶ ۷۸۹) خودش همراه درخواست می‌رود.»
String idGoesLine(String id) => 'شناسه‌ی این رایانه (${idFa(id)}) خودش همراه درخواست می‌رود.';

// C4.4
const kConnectTitle = 'اتصال کارشناس به این رایانه';
const kAllowButton = 'اجازه‌ی اتصال به این رایانه';
const kEndSession = 'پایان جلسه';
const kChatTitle = 'گفت‌وگو';
const kMessageHint = 'پیام…';
const kAttachTooltip = 'فرستادن فایل';
const kFilesTitle = 'فایل‌ها';
const kNoFiles = 'هنوز فایلی نیست.';
const kDownload = 'دریافت';
const kCancelRequest = 'لغو درخواست';
const kClosedNote = 'این درخواست بسته شده است. برای کار تازه، «درخواست تازه» بفرستید.';
const kResultTitle = 'نتیجه';
const kNoMessages = 'هنوز پیامی نیست.';
const kAllowInSession = 'تا کارشناس وصل است لازم نیست؛ پس از پایان جلسه دوباره می‌شود.';
const kNewCodeHint = 'رمز قبلی استفاده شد. اگر کارشناس خواست دوباره وصل شود، همین دکمه رمز تازه را می‌فرستد.';
const kFileLimits = 'تا ۵۰۰ مگابایت؛ فایل‌ها ۱۴ روز می‌مانند.';

/// What the connect box says above the button: who, and what the press sends (never the code itself).
String connectLead(ConnectInfo c) {
  final who = 'کارشناس: ${c.technicianName ?? 'کارشناس دلفین'}.';
  return c.codeMode
      ? '$who با این دکمه شناسه و رمز یک‌بارمصرف همین رایانه به پورتال می‌رود؛ لازم نیست چیزی بخوانید یا تایپ کنید.'
      : '$who با این دکمه شناسه‌ی همین رایانه به پورتال می‌رود. وقتی کارشناس وصل شد، اگر نامش درست بود «پذیرفتن» را بزنید.';
}

/// The live session's line.
String liveLine(ConnectInfo c) =>
    '${c.technicianName ?? 'کارشناس دلفین'} اجازه‌ی اتصال به این رایانه را دارد؛ هر وقت بخواهید می‌توانید پایان دهید.';

// C4.5
const kAccountTitle = 'حساب';
const kCustomerRole = 'مشتری';
const kCurrentPassword = 'رمز فعلی';
const kNewPassword = 'رمز تازه';
const kRepeatPassword = 'تکرار رمز تازه';
const kSave = 'ذخیره';
const kSignOutButton = 'خروج از این رایانه';
const kSignOutLine = '«خروج» نشست را در پورتال هم می‌بندد و ورود ذخیره‌شده را از این رایانه پاک می‌کند.';
const kMustChangeLine = 'پیش از ادامه، رمزی بگذارید که فقط خودتان بدانید.';
const kPasswordRule = 'دست‌کم ۱۰ نویسه.';

Widget _scrollBody(List<Widget> children, {EdgeInsets padding = const EdgeInsets.fromLTRB(14, 12, 14, 14)}) =>
    SingleChildScrollView(
      padding: padding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );

Widget _screen(List<Widget> children) => DolphinLight(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: ColoredBox(color: DolphinColors.ground, child: Column(children: children)),
      ),
    );

BoxDecoration _card() => BoxDecoration(
      color: DolphinColors.surface,
      borderRadius: BorderRadius.circular(DolphinRadii.card),
      border: Border.all(color: DolphinColors.line),
    );

ButtonStyle _danger() => OutlinedButton.styleFrom(
    foregroundColor: DolphinColors.dangerText,
    backgroundColor: DolphinColors.surface,
    side: BorderSide(color: DolphinColors.dangerText));

// ---------------------------------------------------------------------------------------------------------------
// C4.1 sign-in, the first time only

class CustomerSignInView extends StatelessWidget {
  final TextEditingController username;
  final TextEditingController password;
  final bool busy;
  final String? error;

  /// The portal ended the last sign-in: say so above the form.
  final bool expired;
  final String phone;
  final VoidCallback onSubmit;
  final VoidCallback? onBack;
  const CustomerSignInView(
      {super.key,
      required this.username,
      required this.password,
      required this.onSubmit,
      this.busy = false,
      this.error,
      this.expired = false,
      this.phone = '',
      this.onBack});

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    return _screen([
      CustomerBar(title: kRequestsTitle, onBack: onBack),
      Expanded(
        child: _scrollBody([
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                decoration: _card(),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Icon(Icons.support_agent_outlined, size: 34, color: DolphinColors.azureText),
                  const SizedBox(height: 8),
                  Text(kSignInHeading,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: DolphinColors.ink)),
                  const SizedBox(height: 4),
                  Text(kSignInLead,
                      textAlign: TextAlign.center, style: TextStyle(color: DolphinColors.muted, fontSize: 12.5, height: 1.6)),
                  const SizedBox(height: 14),
                  if (expired) ...[
                    const CustomerNotice(kSignInExpiredText, tone: NoticeTone.warning),
                    const SizedBox(height: 12),
                  ],
                  CustomerField(
                    fieldKey: const ValueKey('c4-username'),
                    label: kUsernameLabel,
                    controller: username,
                    enabled: !busy,
                    direction: TextDirection.ltr,
                    autofocus: true,
                  ),
                  const SizedBox(height: 10),
                  CustomerField(
                    fieldKey: const ValueKey('c4-password'),
                    label: kPasswordLabel,
                    controller: password,
                    obscure: true,
                    enabled: !busy,
                    direction: TextDirection.ltr,
                    onSubmitted: busy ? null : (_) => onSubmit(),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    CustomerNotice(error, tone: NoticeTone.error),
                  ],
                  const SizedBox(height: 14),
                  FilledButton(
                    key: const ValueKey('c4-signin'),
                    onPressed: busy ? null : onSubmit,
                    child: busy
                        ? SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: DolphinColors.onFill))
                        : const Text(kSignInButton),
                  ),
                  const SizedBox(height: 12),
                  Text(noAccountLine(phone),
                      textAlign: TextAlign.center, style: TextStyle(color: DolphinColors.muted, fontSize: 12.5, height: 1.6)),
                ]),
              ),
            ),
          ),
        ], padding: const EdgeInsets.fromLTRB(14, 18, 14, 14)),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------
// C4.2 the list

enum AccountChoice { password, signOut }

class CustomerListView extends StatelessWidget {
  final CustomerInfo customer;
  final CustomerScope scope;

  /// Null while the first read runs.
  final List<CustomerRequestRow>? rows;

  /// How many open requests there are (for «باز ۲»); null when unknown.
  final int? openCount;
  final String? error;
  final DateTime now;
  final ValueChanged<CustomerScope> onScope;
  final ValueChanged<CustomerRequestRow> onOpen;
  final VoidCallback onNew;
  final ValueChanged<AccountChoice> onAccount;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;
  const CustomerListView(
      {super.key,
      required this.customer,
      required this.scope,
      required this.rows,
      required this.now,
      required this.onScope,
      required this.onOpen,
      required this.onNew,
      required this.onAccount,
      this.openCount,
      this.error,
      this.onRetry,
      this.onBack});

  Widget _tab(String label, bool on, VoidCallback onTap, Key key) => Semantics(
        selected: on,
        button: true,
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: on ? DolphinColors.azure : DolphinColors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: on ? DolphinColors.azure : DolphinColors.lineStrong),
            ),
            child: Text(label,
                style: TextStyle(
                    color: on ? DolphinColors.onFill : DolphinColors.ink, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ),
      );

  Widget _row(CustomerRequestRow r) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: DolphinColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DolphinRadii.control), side: BorderSide(color: DolphinColors.line)),
          child: InkWell(
            key: ValueKey('c4-row-${r.id}'),
            onTap: () => onOpen(r),
            borderRadius: BorderRadius.circular(DolphinRadii.control),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Text(r.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: r.unread ? FontWeight.w800 : FontWeight.w700, fontSize: 14, color: DolphinColors.ink)),
                  ),
                  if (r.unread) ...[
                    const SizedBox(width: 8),
                    Semantics(
                      label: kUnreadDotLabel,
                      child: Container(
                        key: ValueKey('c4-unread-${r.id}'),
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: DolphinColors.azure, shape: BoxShape.circle),
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: Text(metaLine(r),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: DolphinColors.muted, fontSize: 12.5)),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(r.status),
                ]),
                const SizedBox(height: 4),
                Text(lastLine(r, now),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: DolphinColors.muted, fontSize: 12.5)),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final rows = this.rows, error = this.error, onRetry = this.onRetry, openCount = this.openCount;
    final openLabel = openCount == null || openCount == 0 ? kOpenTab : '$kOpenTab ${faDigits('$openCount')}';
    return _screen([
      CustomerBar(title: kRequestsTitle, onBack: onBack),
      Expanded(
        child: _scrollBody([
          Row(children: [
            Expanded(
              child: Text(kMyRequests, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: DolphinColors.ink)),
            ),
            FilledButton.icon(
              key: const ValueKey('c4-new'),
              onPressed: onNew,
              icon: const Icon(Icons.add, size: 18),
              label: const Text(kNewRequest),
              style: FilledButton.styleFrom(minimumSize: const Size(64, 38)),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _tab(openLabel, scope == CustomerScope.open, () => onScope(CustomerScope.open), const ValueKey('c4-tab-open')),
            _tab(kClosedTab, scope == CustomerScope.closed, () => onScope(CustomerScope.closed),
                const ValueKey('c4-tab-closed')),
          ]),
          const SizedBox(height: 12),
          if (error != null) ...[
            CustomerNotice(error, tone: NoticeTone.error),
            if (onRetry != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(onPressed: onRetry, child: const Text(kRetry)),
              ),
          ] else if (rows == null)
            const CustomerLoading()
          else if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(scope == CustomerScope.open ? kNoOpen : kNoClosed,
                  textAlign: TextAlign.center, style: TextStyle(color: DolphinColors.muted, fontSize: 13, height: 1.7)),
            )
          else
            for (final r in rows) _row(r),
        ]),
      ),
      _AccountFooter(customer: customer, onAccount: onAccount),
    ]);
  }
}

/// C4.2's footer: «username · organization» and «حساب ▾», which opens its two choices right above it, inside the window
/// (a popup menu would be placed by the app's own text direction, not ours).
class _AccountFooter extends StatefulWidget {
  final CustomerInfo customer;
  final ValueChanged<AccountChoice> onAccount;
  const _AccountFooter({required this.customer, required this.onAccount});

  @override
  State<_AccountFooter> createState() => _AccountFooterState();
}

class _AccountFooterState extends State<_AccountFooter> {
  bool _open = false;

  void _choose(AccountChoice c) {
    setState(() => _open = false);
    widget.onAccount(c);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.customer;
    return Container(
      decoration: BoxDecoration(color: DolphinColors.surface, border: Border(top: BorderSide(color: DolphinColors.line))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
            child: Wrap(alignment: WrapAlignment.end, spacing: 6, runSpacing: 6, children: [
              OutlinedButton.icon(
                key: const ValueKey('c4-account-password'),
                onPressed: () => _choose(AccountChoice.password),
                icon: const Icon(Icons.key_outlined, size: 17),
                label: const Text(kChangePasswordItem),
                style: OutlinedButton.styleFrom(minimumSize: const Size(64, 38), backgroundColor: DolphinColors.surface),
              ),
              OutlinedButton.icon(
                key: const ValueKey('c4-account-signout'),
                onPressed: () => _choose(AccountChoice.signOut),
                icon: const Icon(Icons.logout, size: 17),
                label: const Text(kSignOutItem),
                style: _danger().merge(OutlinedButton.styleFrom(minimumSize: const Size(64, 38))),
              ),
            ]),
          ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 2, 4, 2),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(children: [
              Expanded(
                child: Text('${c.username} · ${c.organizationName}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: DolphinColors.muted, fontSize: 12.5)),
              ),
              Semantics(
                button: true,
                expanded: _open,
                child: InkWell(
                  key: const ValueKey('c4-account'),
                  onTap: () => setState(() => _open = !_open),
                  borderRadius: BorderRadius.circular(DolphinRadii.field),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(kAccountMenu,
                          style: TextStyle(color: DolphinColors.azureText, fontSize: 13, fontWeight: FontWeight.w700)),
                      Icon(_open ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 20, color: DolphinColors.azureText),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// C4.3 a new request

class CustomerNewRequestView extends StatelessWidget {
  final List<Product> products;
  final String? productId;
  final TextEditingController subject;
  final TextEditingController description;

  /// This PC's ID, sent with the request; '' while unknown (the line is then left out).
  final String id;

  /// The web's «فوری است» box (priority urgent); off by default.
  final bool urgent;
  final ValueChanged<bool>? onUrgent;

  /// «عکس صفحه را هم بفرست»: off by default; null hides it (no screenshot on this PC).
  final bool screenshot;
  final ValueChanged<bool>? onScreenshot;
  final bool busy;
  final String? error;
  final ValueChanged<String?> onProduct;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  const CustomerNewRequestView(
      {super.key,
      required this.products,
      required this.subject,
      required this.description,
      required this.id,
      required this.onProduct,
      required this.onSend,
      required this.onCancel,
      this.productId,
      this.urgent = false,
      this.onUrgent,
      this.screenshot = false,
      this.onScreenshot,
      this.busy = false,
      this.error});

  @override
  Widget build(BuildContext context) {
    final onScreenshot = this.onScreenshot, onUrgent = this.onUrgent, error = this.error;
    Widget toggle(String label, bool value, ValueChanged<bool> onChanged, Key key) => InkWell(
          onTap: busy ? null : () => onChanged(!value),
          borderRadius: BorderRadius.circular(DolphinRadii.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(child: Text(label, style: TextStyle(color: DolphinColors.ink, fontSize: 13.5))),
              Switch(key: key, value: value, onChanged: busy ? null : onChanged),
            ]),
          ),
        );
    return _screen([
      CustomerBar(title: kNewRequest, onBack: busy ? null : onCancel),
      Expanded(
        child: _scrollBody([
          if (products.isNotEmpty) ...[
            Text(kProductLabel, style: TextStyle(color: DolphinColors.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              key: const ValueKey('c4-product'),
              value: productId ?? '',
              isExpanded: true,
              dropdownColor: DolphinColors.surface,
              decoration: customerInput(),
              style: TextStyle(color: DolphinColors.ink, fontSize: 14, fontFamily: kDolphinFont),
              iconEnabledColor: DolphinColors.muted,
              items: [
                DropdownMenuItem(value: '', child: Text(kProductUnknown, style: TextStyle(color: DolphinColors.ink))),
                for (final p in products)
                  DropdownMenuItem(
                      value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis, style: TextStyle(color: DolphinColors.ink))),
              ],
              onChanged: busy ? null : (v) => onProduct(v == null || v.isEmpty ? null : v),
            ),
            const SizedBox(height: 10),
          ],
          CustomerField(
              fieldKey: const ValueKey('c4-subject'),
              label: kSubjectLabel,
              controller: subject,
              enabled: !busy,
              maxLength: 200,
              hint: 'مثلاً: خطا هنگام چاپ فاکتور'),
          const SizedBox(height: 10),
          CustomerField(
              fieldKey: const ValueKey('c4-description'),
              label: kDescriptionLabel,
              controller: description,
              enabled: !busy,
              minLines: 3,
              maxLines: 6,
              maxLength: 5000,
              hint: 'چه اتفاقی افتاد و در کدام نرم‌افزار؟'),
          const SizedBox(height: 6),
          if (onUrgent != null) toggle(kUrgentSwitch, urgent, onUrgent, const ValueKey('c4-urgent')),
          if (onScreenshot != null) toggle(kScreenshotSwitch, screenshot, onScreenshot, const ValueKey('c4-screenshot')),
          if (id.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration:
                  BoxDecoration(color: DolphinColors.azureSoft, borderRadius: BorderRadius.circular(DolphinRadii.control)),
              child: Text(idGoesLine(id), style: TextStyle(color: DolphinColors.azureText, fontSize: 12.5, height: 1.6)),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 10),
            CustomerNotice(error, tone: NoticeTone.error),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: FilledButton(
                key: const ValueKey('c4-send-request'),
                onPressed: busy ? null : onSend,
                child: busy
                    ? SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: DolphinColors.onFill))
                    : const Text(kSendButton),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: busy ? null : onCancel, child: const Text(kCancelButton))),
          ]),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------
// C4.4 one request: connect, chat, files

/// A file being sent: its name and how far it got.
class UploadProgress {
  final String name;
  final int received;
  final int size;
  const UploadProgress(this.name, this.received, this.size);
}

class CustomerRequestView extends StatelessWidget {
  final CustomerRequestDetail detail;
  final DateTime now;
  final TextEditingController message;

  /// A technician is connected to this PC now (or it is not known yet): the allow button waits.
  final bool connectedNow;
  final bool allowBusy;
  final bool sendBusy;
  final bool endBusy;
  final UploadProgress? upload;

  /// A result of the last action (sent, saved, refused), with its tone.
  final String? notice;
  final NoticeTone noticeTone;
  final VoidCallback onBack;
  final VoidCallback onAllow;
  final VoidCallback onEndSession;
  final VoidCallback onSend;

  /// 📎: null hides it (no picker, or the server keeps no files).
  final VoidCallback? onAttach;
  final ValueChanged<RequestFile>? onDownload;
  final VoidCallback? onCancelRequest;
  const CustomerRequestView(
      {super.key,
      required this.detail,
      required this.now,
      required this.message,
      required this.onBack,
      required this.onAllow,
      required this.onEndSession,
      required this.onSend,
      this.connectedNow = false,
      this.allowBusy = false,
      this.sendBusy = false,
      this.endBusy = false,
      this.upload,
      this.notice,
      this.noticeTone = NoticeTone.info,
      this.onAttach,
      this.onDownload,
      this.onCancelRequest});

  CustomerRequestRow get _row => detail.row;

  /// The allow button shows while the portal asks for this PC, and again after a used code (WF-15).
  bool get _allowShown {
    final c = detail.connect;
    if (!_row.open) return false;
    if (c.sessionLive) return c.codeMode && c.codeState == CodeState.used;
    return c.show;
  }

  Widget _connectBox() {
    final c = detail.connect;
    final edge = Color.lerp(DolphinColors.aquaSoft, DolphinColors.aqua, 0.35)!;
    final expires = c.codeExpiresAt;
    return Container(
      key: const ValueKey('c4-connect-box'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: DolphinColors.aquaSoft,
          borderRadius: BorderRadius.circular(DolphinRadii.control),
          border: Border.all(color: edge)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(kConnectTitle, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: DolphinColors.ink)),
        const SizedBox(height: 4),
        Text(connectLead(c), style: TextStyle(color: DolphinColors.ink, fontSize: 12.5, height: 1.7)),
        if (c.codeMode && c.codeState == CodeState.used) ...[
          const SizedBox(height: 6),
          Text(kNewCodeHint, style: TextStyle(color: DolphinColors.amberText, fontSize: 12.5, height: 1.6)),
        ],
        if (c.codeMode && c.codeSubmitted && expires != null) ...[
          const SizedBox(height: 6),
          Text('رمز ثبت شد؛ معتبر تا ساعت ${clockFa(expires)}.',
              style: TextStyle(color: DolphinColors.aquaText, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 10),
        FilledButton.icon(
          key: const ValueKey('c4-allow'),
          onPressed: allowBusy || connectedNow ? null : onAllow,
          icon: allowBusy
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: DolphinColors.onFill))
              : const Icon(Icons.screen_share_outlined, size: 18),
          label: const Text(kAllowButton),
          style: FilledButton.styleFrom(
            backgroundColor: DolphinColors.accentFill,
            foregroundColor: DolphinColors.onFill,
            disabledBackgroundColor: DolphinColors.line,
            disabledForegroundColor: DolphinColors.muted,
          ),
        ),
        if (connectedNow) ...[
          const SizedBox(height: 6),
          Text(kAllowInSession, style: TextStyle(color: DolphinColors.muted, fontSize: 12, height: 1.6)),
        ],
      ]),
    );
  }

  Widget _liveBox() {
    final c = detail.connect;
    return Container(
      key: const ValueKey('c4-live-box'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: DolphinColors.azureSoft,
          borderRadius: BorderRadius.circular(DolphinRadii.control),
          border: Border.all(color: DolphinColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.screen_share_outlined, size: 18, color: DolphinColors.azureText),
          const SizedBox(width: 8),
          Expanded(
              child: Text('جلسه‌ی پشتیبانی باز است',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: DolphinColors.azureText))),
        ]),
        const SizedBox(height: 4),
        Text(liveLine(c), style: TextStyle(color: DolphinColors.ink, fontSize: 12.5, height: 1.7)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('c4-end-session'),
          onPressed: endBusy ? null : onEndSession,
          icon: const Icon(Icons.link_off, size: 18),
          label: const Text(kEndSession),
          style: _danger(),
        ),
      ]),
    );
  }

  Widget _bubble(RequestMessage m) {
    final mine = !m.fromStaff;
    final who = mine ? 'شما' : (m.authorName.isEmpty ? 'دلفین' : m.authorName);
    return Align(
      // RTL: the customer's own on the start (right), Dolphin's on the end (left), as the design draws them.
      alignment: mine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
      child: FractionallySizedBox(
        widthFactor: 0.86,
        alignment: mine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
        child: Align(
          alignment: mine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            decoration: BoxDecoration(
              color: mine ? DolphinColors.azureSoft : DolphinColors.surface,
              borderRadius: BorderRadius.circular(DolphinRadii.control),
              border: Border.all(color: DolphinColors.line),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('$who · ${shortTimeFa(m.at, now)}', style: TextStyle(color: DolphinColors.muted, fontSize: 11.5)),
              const SizedBox(height: 2),
              SelectableText(m.body, style: TextStyle(color: DolphinColors.ink, fontSize: 13.5, height: 1.6)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _files(List<RequestFile> files) {
    final onDownload = this.onDownload, upload = this.upload;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(kFilesTitle, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: DolphinColors.ink)),
      const SizedBox(height: 6),
      if (files.isEmpty && upload == null)
        Text(kNoFiles, style: TextStyle(color: DolphinColors.muted, fontSize: 12.5)),
      for (final f in files)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsetsDirectional.fromSTEB(10, 4, 4, 4),
          decoration: BoxDecoration(
              color: DolphinColors.surface,
              borderRadius: BorderRadius.circular(DolphinRadii.control),
              border: Border.all(color: DolphinColors.line)),
          child: Row(children: [
            Icon(Icons.insert_drive_file_outlined, size: 18, color: DolphinColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(f.name,
                    textDirection: TextDirection.ltr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: DolphinColors.ink, fontSize: 13, fontWeight: FontWeight.w600)),
                Text('${sizeFa(f.size)} · ${f.mine ? 'شما' : 'دلفین'}',
                    style: TextStyle(color: DolphinColors.muted, fontSize: 11.5)),
              ]),
            ),
            if (onDownload != null)
              TextButton.icon(
                key: ValueKey('c4-download-${f.id}'),
                onPressed: () => onDownload(f),
                icon: const Icon(Icons.download_outlined, size: 17),
                label: const Text(kDownload),
                style: TextButton.styleFrom(minimumSize: const Size(44, 38)),
              ),
          ]),
        ),
      if (upload != null)
        Semantics(
          liveRegion: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('در حال فرستادن ${upload.name}: ${sizeFa(upload.received)} از ${sizeFa(upload.size)}',
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: DolphinColors.ink, fontSize: 12.5)),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: upload.size == 0 ? null : upload.received / upload.size,
              color: DolphinColors.azure,
              backgroundColor: DolphinColors.line,
            ),
          ]),
        ),
      if (_row.open && onAttach != null) ...[
        const SizedBox(height: 4),
        Text(kFileLimits, style: TextStyle(color: DolphinColors.muted, fontSize: 11.5)),
      ],
    ]);
  }

  Widget _composer() {
    final onAttach = this.onAttach;
    return Container(
      decoration: BoxDecoration(color: DolphinColors.surface, border: Border(top: BorderSide(color: DolphinColors.line))),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: TextField(
            key: const ValueKey('c4-message'),
            controller: message,
            enabled: !sendBusy,
            minLines: 1,
            maxLines: 4,
            maxLength: 5000,
            style: TextStyle(color: DolphinColors.ink, fontSize: 14),
            decoration: customerInput(hint: kMessageHint),
          ),
        ),
        if (onAttach != null) ...[
          const SizedBox(width: 4),
          IconButton(
            key: const ValueKey('c4-attach'),
            tooltip: kAttachTooltip,
            onPressed: upload == null ? onAttach : null,
            icon: Icon(Icons.attach_file, color: DolphinColors.muted),
          ),
        ],
        const SizedBox(width: 4),
        FilledButton(
          key: const ValueKey('c4-send-message'),
          onPressed: sendBusy ? null : onSend,
          style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
          child: const Text(kSendButton),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = detail.connect, notice = this.notice, files = detail.files, result = detail.result;
    final onCancelRequest = this.onCancelRequest;
    return _screen([
      CustomerBar(
        title: requestNumberFa(_row.number),
        onBack: onBack,
        trailing: StatusChip(_row.status),
      ),
      Expanded(
        child: _scrollBody([
          Text(_row.subject,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: DolphinColors.ink, height: 1.5)),
          if ((_row.product ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(_row.product!, style: TextStyle(color: DolphinColors.muted, fontSize: 12.5)),
          ],
          if (detail.description.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(detail.description.trim(),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: DolphinColors.muted, fontSize: 13, height: 1.7)),
          ],
          if (_row.open && c.sessionLive) ...[const SizedBox(height: 12), _liveBox()],
          if (_allowShown) ...[const SizedBox(height: 12), _connectBox()],
          if (notice != null) ...[const SizedBox(height: 10), CustomerNotice(notice, tone: noticeTone)],
          if (_row.status == 'resolved' && result != null && result.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: _card(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(kResultTitle, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: DolphinColors.ink)),
                const SizedBox(height: 4),
                Text(result.trim(), style: TextStyle(color: DolphinColors.ink, fontSize: 13, height: 1.7)),
              ]),
            ),
          ],
          const SizedBox(height: 14),
          Text(kChatTitle, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: DolphinColors.ink)),
          const SizedBox(height: 6),
          if (detail.messages.isEmpty) Text(kNoMessages, style: TextStyle(color: DolphinColors.muted, fontSize: 12.5)),
          for (final m in detail.messages) _bubble(m),
          if (!_row.open) ...[
            const SizedBox(height: 4),
            Text(kClosedNote, style: TextStyle(color: DolphinColors.muted, fontSize: 12.5, height: 1.6)),
          ],
          if (files != null) ...[const SizedBox(height: 14), _files(files)],
          if (onCancelRequest != null && _row.cancellable) ...[
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: const ValueKey('c4-cancel-request'),
                onPressed: onCancelRequest,
                style: TextButton.styleFrom(foregroundColor: DolphinColors.dangerText),
                child: const Text(kCancelRequest),
              ),
            ),
          ],
        ]),
      ),
      if (_row.open) _composer(),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------
// C4.5 account

class CustomerAccountView extends StatelessWidget {
  final CustomerInfo customer;

  /// UN-10: the password must change before anything else (no way back, only this and «خروج»).
  final bool forced;
  final TextEditingController current;
  final TextEditingController next;
  final TextEditingController repeat;
  final bool busy;
  final String? error;
  final String? message;
  final VoidCallback onSave;
  final VoidCallback onSignOut;
  final VoidCallback? onBack;
  const CustomerAccountView(
      {super.key,
      required this.customer,
      required this.current,
      required this.next,
      required this.repeat,
      required this.onSave,
      required this.onSignOut,
      this.forced = false,
      this.busy = false,
      this.error,
      this.message,
      this.onBack});

  @override
  Widget build(BuildContext context) {
    final error = this.error, message = this.message;
    return _screen([
      CustomerBar(title: kAccountTitle, onBack: forced || busy ? null : onBack),
      Expanded(
        child: _scrollBody([
          Container(
            padding: const EdgeInsets.all(12),
            decoration: _card(),
            child: Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: DolphinColors.azureSoft,
                child: Icon(Icons.person_outline, size: 20, color: DolphinColors.azureText),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(customer.username,
                      textDirection: TextDirection.ltr,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: DolphinColors.ink)),
                  Text('${customer.organizationName} · $kCustomerRole',
                      overflow: TextOverflow.ellipsis, style: TextStyle(color: DolphinColors.muted, fontSize: 12.5)),
                ]),
              ),
            ]),
          ),
          if (forced) ...[const SizedBox(height: 10), const CustomerNotice(kMustChangeLine, tone: NoticeTone.warning)],
          const SizedBox(height: 14),
          Text(kChangePasswordItem, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: DolphinColors.ink)),
          const SizedBox(height: 8),
          CustomerField(
              fieldKey: const ValueKey('c4-current'),
              label: kCurrentPassword,
              controller: current,
              obscure: true,
              enabled: !busy,
              direction: TextDirection.ltr),
          const SizedBox(height: 8),
          CustomerField(
              fieldKey: const ValueKey('c4-next'),
              label: kNewPassword,
              controller: next,
              obscure: true,
              enabled: !busy,
              direction: TextDirection.ltr),
          const SizedBox(height: 8),
          CustomerField(
              fieldKey: const ValueKey('c4-repeat'),
              label: kRepeatPassword,
              controller: repeat,
              obscure: true,
              enabled: !busy,
              direction: TextDirection.ltr,
              onSubmitted: busy ? null : (_) => onSave()),
          const SizedBox(height: 4),
          Text(kPasswordRule, style: TextStyle(color: DolphinColors.muted, fontSize: 12)),
          if (error != null) ...[const SizedBox(height: 8), CustomerNotice(error, tone: NoticeTone.error)],
          if (message != null) ...[const SizedBox(height: 8), CustomerNotice(message, tone: NoticeTone.success)],
          const SizedBox(height: 10),
          FilledButton(
            key: const ValueKey('c4-save-password'),
            onPressed: busy ? null : onSave,
            child: const Text(kSave),
          ),
          const SizedBox(height: 18),
          Divider(height: 1, color: DolphinColors.line),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const ValueKey('c4-signout'),
            onPressed: busy ? null : onSignOut,
            icon: const Icon(Icons.logout, size: 18),
            label: const Text(kSignOutButton),
            style: _danger(),
          ),
          const SizedBox(height: 6),
          Text(kSignOutLine, style: TextStyle(color: DolphinColors.muted, fontSize: 12, height: 1.6)),
        ]),
      ),
    ]);
  }
}

/// A screen whose content is still being read, or could not be: the bar, then the wait or the error with «تلاش دوباره».
class CustomerWaitView extends StatelessWidget {
  final String title;
  final String? error;
  final VoidCallback? onBack;
  final VoidCallback? onRetry;
  const CustomerWaitView({super.key, required this.title, this.error, this.onBack, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final error = this.error, onRetry = this.onRetry;
    return _screen([
      CustomerBar(title: title, onBack: onBack),
      Expanded(
        child: _scrollBody([
          if (error == null)
            const CustomerLoading()
          else ...[
            CustomerNotice(error, tone: NoticeTone.error),
            if (onRetry != null)
              Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(onPressed: onRetry, child: const Text(kRetry))),
          ],
        ]),
      ),
    ]);
  }
}
