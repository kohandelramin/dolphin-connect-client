import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'customer_api/api.dart';
import 'customer_api/session.dart';
import 'customer_ui/views.dart';
import 'customer_ui/widgets.dart';
import 'panel_bridge.dart' show panelCodePattern, panelIdPattern;
import 'support_upload.dart' show UploadKind;
import 'support_views.dart';
import 'theme.dart';

export 'customer_ui/views.dart' show kRequestsTitle;

/// Plan 19 C4: the customer build's «درخواست‌ها و پیام‌ها», native (it was the customer portal in WebView2 until 2.2.0;
/// the browser portal stays). Sign-in (C4.1), the list (C4.2), a new request (C4.3), one request (C4.4) and the account
/// (C4.5), on the customer App API. The views are pure (customer_ui/views.dart); this holds the state.
///
/// Consent (SECURITY.md, do not bend): «اجازه‌ی اتصال به این رایانه» sends this PC's ID; in code mode also the current
/// one-time password, read through [DolphinCustomerRequests.readCode] only inside that press, kept in a local variable
/// for that one request, never shown, never logged. In click mode the code is never read: the customer still presses
/// «پذیرفتن» in the accept prompt. While a technician is connected the button waits, and a press the technician made
/// remotely is ignored ([DolphinCustomerRequests.pressIsLocal], upstream's rule in access_profile.dart).

/// A file the customer picked with Windows' file picker.
class ChosenFile {
  final String path;
  final String name;
  final int size;
  const ChosenFile(this.path, this.name, this.size);
}

const kMsgCodeNotReady = 'رمز یک‌بارمصرف این رایانه هنوز آماده نیست؛ چند ثانیه بعد دوباره «اجازه‌ی اتصال» را بزنید.';
const kMsgIdNotReady = 'شناسه‌ی این رایانه هنوز آماده نیست؛ چند ثانیه بعد دوباره امتحان کنید.';
const kMsgAllowed = 'ثبت شد. کارشناس دلفین به‌زودی وصل می‌شود. پنجره‌ی برنامه را باز نگه دارید.';
const kMsgWriteMessage = 'متن پیام را بنویسید.';
const kMsgFileSent = 'فایل فرستاده شد.';
const kMsgFileSaved = 'فایل ذخیره شد.';
const kMsgShotFailed = 'عکس صفحه گرفته نشد؛ بدون عکس بفرستید یا دوباره امتحان کنید.';
const kMsgShotNotSent = 'درخواست ثبت شد، ولی عکس صفحه فرستاده نشد: ';
const kMsgEnded = 'جلسه پایان یافت.';
const kCancelQuestion = 'این درخواست لغو شود؟';
const kCancelYes = 'لغو درخواست';
const kCancelNo = 'نه';

/// An open request is read again this often while it is on screen (the web page refreshes every 10 s).
const kRequestRefresh = Duration(seconds: 10);

enum _Page { list, create, request, account }

class DolphinCustomerRequests extends StatefulWidget {
  final CustomerSession session;

  /// C4.6's count; read again after a request was viewed.
  final UnreadPoller? unread;

  /// This PC's ID (shown in C4.3, sent with a new request and with «اجازه‌ی اتصال»).
  final String id;

  /// Code mode only: this PC's current one-time password, as the home's code card reads it ('' when there is none or
  /// the organization is in click mode). Called only inside the customer's press of «اجازه‌ی اتصال به این رایانه».
  final String Function() readCode;

  /// A technician is connected to this PC now, or the count is not known yet.
  final bool connectedNow;

  /// True when the press just made was the customer's own, not the technician's from his side.
  final Future<bool> Function()? pressIsLocal;

  /// DD-48: this PC's screen as PNG (the window steps aside first); null hides «عکس صفحه را هم بفرست».
  final Future<Uint8List?> Function()? takeScreenshot;

  /// Windows' file picker for 📎; null hides it.
  final Future<ChosenFile?> Function()? pickFile;

  /// Windows' save dialog for «دریافت»: the path chosen, or null.
  final Future<String?> Function(String name)? saveAs;
  final String phone;
  final VoidCallback onBack;

  /// Null: no automatic refresh (tests).
  final Duration? refreshEvery;
  final DateTime Function() now;

  const DolphinCustomerRequests(
      {super.key,
      required this.session,
      required this.id,
      required this.readCode,
      required this.onBack,
      this.unread,
      this.connectedNow = false,
      this.pressIsLocal,
      this.takeScreenshot,
      this.pickFile,
      this.saveAs,
      this.phone = '',
      this.refreshEvery = kRequestRefresh,
      this.now = DateTime.now});

  @override
  State<DolphinCustomerRequests> createState() => _DolphinCustomerRequestsState();
}

class _DolphinCustomerRequestsState extends State<DolphinCustomerRequests> {
  CustomerSession get _session => widget.session;
  CustomerApi get _api => widget.session.api;

  _Page _page = _Page.list;

  /// Whose data this screen holds: everything is dropped when it changes (sign-out, another customer).
  String? _holder;

  CustomerScope _scope = CustomerScope.open;
  List<CustomerRequestRow>? _rows;
  int? _openCount;
  String? _listError;
  bool _listLoading = false;

  String? _requestId;
  CustomerRequestDetail? _detail;
  String? _detailError;
  bool _allowBusy = false, _sendBusy = false, _endBusy = false;
  UploadProgress? _upload;
  String? _notice;
  NoticeTone _noticeTone = NoticeTone.info;

  List<Product> _products = const [];
  bool _productsRead = false;
  String? _productId;
  bool _shot = false;
  bool _urgent = false;
  bool _createBusy = false;
  String? _createError;

  bool _pwBusy = false;
  String? _pwError, _pwMessage;

  final _username = TextEditingController();
  final _password = TextEditingController();
  final _subject = TextEditingController();
  final _description = TextEditingController();
  final _message = TextEditingController();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();

  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSession);
    widget.unread?.count.addListener(_onUnread);
    _onSession();
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _session.removeListener(_onSession);
    widget.unread?.count.removeListener(_onUnread);
    for (final c in [_username, _password, _subject, _description, _message, _current, _next, _repeat]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onSession() {
    final who = _session.signedIn ? _session.customer?.id : null;
    if (who != _holder) {
      _clear();
      _holder = who;
    }
    if (_session.ready && _rows == null && _listError == null && !_listLoading) unawaited(_loadList());
    if (mounted) setState(() {});
  }

  /// A new count: the list shows the new dots.
  void _onUnread() {
    if (_page == _Page.list && _session.ready && !_listLoading) unawaited(_loadList());
  }

  /// Customer A's data never stays for customer B: every row, request, product and typed text goes.
  void _clear() {
    _refresh?.cancel();
    _refresh = null;
    _page = _Page.list;
    _scope = CustomerScope.open;
    _rows = null;
    _openCount = null;
    _listError = null;
    _requestId = null;
    _detail = null;
    _detailError = null;
    _upload = null;
    _notice = null;
    _products = const [];
    _productsRead = false;
    _productId = null;
    _shot = false;
    _urgent = false;
    _createError = null;
    _pwError = null;
    _pwMessage = null;
    for (final c in [_subject, _description, _message, _current, _next, _repeat, _password]) {
      c.clear();
    }
  }

  bool _mine(String? holder) => mounted && holder == _holder;

  // ---- C4.1

  Future<void> _signIn() async {
    final ok = await _session.signIn(_username.text, _password.text);
    _password.clear();
    if (ok) _username.clear();
  }

  // ---- C4.2

  Future<void> _loadList() async {
    final holder = _holder, scope = _scope;
    _listLoading = true;
    try {
      final rows = await _api.requests(scope);
      if (!_mine(holder) || scope != _scope) return;
      setState(() {
        _rows = rows;
        _listError = null;
        if (scope == CustomerScope.open) _openCount = rows.length;
      });
    } on SignInExpired {
      // The session store shows the sign-in.
    } catch (e) {
      if (_mine(holder) && scope == _scope) setState(() => _listError = apiErrorText(e));
    } finally {
      _listLoading = false;
    }
  }

  void _setScope(CustomerScope s) {
    if (s == _scope) return;
    setState(() {
      _scope = s;
      _rows = null;
      _listError = null;
    });
    unawaited(_loadList());
  }

  void _toList() {
    _refresh?.cancel();
    _refresh = null;
    setState(() {
      _page = _Page.list;
      _requestId = null;
      _detail = null;
      _detailError = null;
      _notice = null;
      _message.clear();
    });
    unawaited(_loadList());
  }

  void _account(AccountChoice c) {
    switch (c) {
      case AccountChoice.password:
        setState(() {
          _page = _Page.account;
          _pwError = null;
          _pwMessage = null;
        });
      case AccountChoice.signOut:
        unawaited(_signOut());
    }
  }

  // ---- C4.3

  void _openCreate() {
    setState(() {
      _page = _Page.create;
      _createError = null;
      _shot = false;
    });
    if (!_productsRead) unawaited(_loadProducts());
  }

  Future<void> _loadProducts() async {
    final holder = _holder;
    try {
      final list = await _api.products();
      if (_mine(holder)) {
        setState(() {
          _products = list;
          _productsRead = true;
        });
      }
    } catch (_) {
      // The form works without a product («نمی‌دانم / دیگر»).
    }
  }

  Future<void> _sendRequest() async {
    if (_createBusy) return;
    if (_subject.text.trim().length < 3 || _description.text.trim().length < 5) {
      setState(() => _createError = kRequestFieldsError);
      return;
    }
    final take = widget.takeScreenshot;
    if (_shot && take != null) {
      setState(() {
        _createBusy = true;
        _createError = null;
      });
      final png = await take();
      if (!mounted) return;
      setState(() => _createBusy = false);
      if (png == null) {
        setState(() => _createError = kMsgShotFailed);
        return;
      }
      // DD-48: the customer sees the picture before anything goes out; «انصراف» sends nothing.
      await showDolphinPanel(context, (close) => _ShotConfirm(png: png, onSend: () => _create(png), onClose: close));
      return;
    }
    setState(() {
      _createBusy = true;
      _createError = null;
    });
    final error = await _create(null);
    if (mounted) {
      setState(() {
        _createBusy = false;
        if (error != null) _createError = error;
      });
    }
  }

  /// Opens the request (this PC's ID with it), then sends [png] as its first file. Null on success; the request then
  /// opens. A refused screenshot still leaves the request open, with a notice.
  Future<String?> _create(Uint8List? png) async {
    final holder = _holder;
    final CreatedRequest created;
    try {
      created = await _api.createRequest(
          productId: _productId,
          subject: _subject.text,
          description: _description.text,
          rustdeskId: panelIdPattern.hasMatch(widget.id) ? widget.id : null,
          urgent: _urgent);
    } catch (e) {
      return apiErrorText(e);
    }
    String? shotError;
    if (png != null) {
      try {
        await _api.upload(created.id,
            name: 'screenshot.png',
            size: png.length,
            read: (o, n) async => png.sublist(o, (o + n).clamp(0, png.length)));
      } catch (e) {
        shotError = apiErrorText(e);
      }
    }
    if (!_mine(holder)) return null;
    _subject.clear();
    _description.clear();
    _productId = null;
    _shot = false;
    _urgent = false;
    _createBusy = false;
    _openRequest(created.id);
    if (shotError != null) {
      setState(() {
        _notice = '$kMsgShotNotSent$shotError';
        _noticeTone = NoticeTone.warning;
      });
    }
    return null;
  }

  // ---- C4.4

  void _openRequest(String id) {
    _refresh?.cancel();
    setState(() {
      _page = _Page.request;
      _requestId = id;
      _detail = null;
      _detailError = null;
      _notice = null;
      _message.clear();
    });
    unawaited(_loadDetail());
    final every = widget.refreshEvery;
    if (every != null) {
      _refresh = Timer.periodic(every, (_) {
        if (_detail?.row.open == true && !_allowBusy && !_sendBusy && _upload == null) unawaited(_loadDetail());
      });
    }
  }

  Future<void> _loadDetail() async {
    final holder = _holder, id = _requestId;
    if (id == null) return;
    try {
      final d = await _api.request(id);
      if (!_mine(holder) || id != _requestId) return;
      setState(() {
        _detail = d;
        _detailError = null;
      });
      unawaited(widget.unread?.poll());
    } on SignInExpired {
      // The session store shows the sign-in.
    } catch (e) {
      // A quiet refresh keeps what is on screen.
      if (_mine(holder) && id == _requestId && _detail == null) setState(() => _detailError = apiErrorText(e));
    }
  }

  void _say(String text, NoticeTone tone) {
    if (mounted) {
      setState(() {
        _notice = text;
        _noticeTone = tone;
      });
    }
  }

  /// «اجازه‌ی اتصال به این رایانه»: the only place the one-time password is read.
  Future<void> _allow() async {
    final d = _detail;
    if (d == null || _allowBusy || widget.connectedNow) return;
    final local = widget.pressIsLocal;
    if (local != null && !await local()) return; // the technician's press from his side: ignored
    if (!mounted || !identical(d, _detail)) return;
    final id = widget.id;
    if (!panelIdPattern.hasMatch(id)) return _say(kMsgIdNotReady, NoticeTone.warning);
    String? code;
    if (d.connect.codeMode) {
      code = widget.readCode();
      if (!panelCodePattern.hasMatch(code)) return _say(kMsgCodeNotReady, NoticeTone.warning);
    }
    setState(() {
      _allowBusy = true;
      _notice = null;
    });
    try {
      final said = await _api.allowConnect(d.row.id, rustdeskId: id, code: code);
      _say(said ?? kMsgAllowed, NoticeTone.success);
    } catch (e) {
      // The portal's normal next steps (notice: true) are information, not errors.
      _say(apiErrorText(e), isNextStep(e) ? NoticeTone.info : NoticeTone.error);
    } finally {
      code = null;
    }
    if (mounted) setState(() => _allowBusy = false);
    await _loadDetail();
  }

  Future<void> _endSession() async {
    final d = _detail;
    if (d == null || _endBusy) return;
    setState(() => _endBusy = true);
    try {
      await _api.endSession(d.row.id);
      _say(kMsgEnded, NoticeTone.success);
    } catch (e) {
      _say(apiErrorText(e), NoticeTone.error);
    }
    if (mounted) setState(() => _endBusy = false);
    await _loadDetail();
  }

  Future<void> _sendMessage() async {
    final d = _detail;
    if (d == null || _sendBusy) return;
    final text = _message.text.trim();
    if (text.isEmpty) return _say(kMsgWriteMessage, NoticeTone.warning);
    setState(() {
      _sendBusy = true;
      _notice = null;
    });
    try {
      await _api.sendMessage(d.row.id, text);
      _message.clear();
    } catch (e) {
      _say(apiErrorText(e), NoticeTone.error);
    }
    if (mounted) setState(() => _sendBusy = false);
    await _loadDetail();
  }

  Future<void> _attach() async {
    final d = _detail, pick = widget.pickFile;
    if (d == null || pick == null || _upload != null) return;
    final f = await pick();
    if (f == null || !mounted) return;
    setState(() {
      _upload = UploadProgress(f.name, 0, f.size);
      _notice = null;
    });
    RandomAccessFile? raf;
    try {
      final open = raf = await File(f.path).open();
      await _api.upload(d.row.id, name: f.name, size: f.size, read: (o, n) async {
        await open.setPosition(o);
        return open.read(n);
      }, onProgress: (r) {
        if (mounted) setState(() => _upload = UploadProgress(f.name, r, f.size));
      });
      _say(kMsgFileSent, NoticeTone.success);
    } catch (e) {
      _say(apiErrorText(e), NoticeTone.error);
    } finally {
      await raf?.close();
    }
    if (mounted) setState(() => _upload = null);
    await _loadDetail();
  }

  Future<void> _download(RequestFile f) async {
    final save = widget.saveAs;
    if (save == null) return;
    final path = await save(f.name);
    if (path == null || !mounted) return;
    try {
      await _api.downloadFile(f.id, File(path), size: f.size);
      _say(kMsgFileSaved, NoticeTone.success);
    } catch (e) {
      _say(apiErrorText(e), NoticeTone.error);
    }
  }

  Future<void> _cancelRequest() async {
    final d = _detail;
    if (d == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => DolphinLight(
        paint: false,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: DolphinColors.surface,
            content: Text(kCancelQuestion, style: TextStyle(color: DolphinColors.ink, fontSize: 14)),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(kCancelNo)),
              FilledButton(
                key: const ValueKey('c4-cancel-yes'),
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(backgroundColor: DolphinColors.danger, foregroundColor: DolphinColors.onFill),
                child: const Text(kCancelYes),
              ),
            ],
          ),
        ),
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await _api.cancel(d.row.id);
    } catch (e) {
      _say(apiErrorText(e), NoticeTone.error);
    }
    await _loadDetail();
  }

  // ---- C4.5

  Future<void> _savePassword() async {
    if (_pwBusy) return;
    setState(() {
      _pwBusy = true;
      _pwError = null;
      _pwMessage = null;
    });
    final forced = _session.mustChangePassword;
    final error = await _session.changePassword(_current.text, _next.text, _repeat.text);
    if (!mounted) return;
    setState(() {
      _pwBusy = false;
      if (error != null) {
        _pwError = error;
      } else {
        _current.clear();
        _next.clear();
        _repeat.clear();
        _pwMessage = _session.lastPasswordMessage ?? kMsgPasswordChanged;
        // UN-10: the first change opens the requests.
        if (forced) _page = _Page.list;
      }
    });
  }

  Future<void> _signOut() => _session.signOut();

  // ---- build

  @override
  Widget build(BuildContext context) {
    final s = _session;
    if (s.state == CustomerSignIn.unknown) return CustomerWaitView(title: kRequestsTitle, onBack: widget.onBack);
    final customer = s.customer;
    if (!s.signedIn || customer == null) {
      return CustomerSignInView(
        username: _username,
        password: _password,
        busy: s.busy,
        error: s.error,
        expired: s.state == CustomerSignIn.expired,
        phone: widget.phone,
        onSubmit: _signIn,
        onBack: widget.onBack,
      );
    }
    if (s.mustChangePassword || _page == _Page.account) {
      return CustomerAccountView(
        customer: customer,
        forced: s.mustChangePassword,
        current: _current,
        next: _next,
        repeat: _repeat,
        busy: _pwBusy,
        error: _pwError,
        message: _pwMessage,
        onSave: _savePassword,
        onSignOut: _signOut,
        onBack: _toList,
      );
    }
    switch (_page) {
      case _Page.create:
        return CustomerNewRequestView(
          products: _products,
          productId: _productId,
          subject: _subject,
          description: _description,
          id: panelIdPattern.hasMatch(widget.id) ? widget.id : '',
          urgent: _urgent,
          onUrgent: (v) => setState(() => _urgent = v),
          screenshot: _shot,
          onScreenshot: widget.takeScreenshot == null ? null : (v) => setState(() => _shot = v),
          busy: _createBusy,
          error: _createError,
          onProduct: (v) => setState(() => _productId = v),
          onSend: _sendRequest,
          onCancel: _toList,
        );
      case _Page.request:
        final d = _detail;
        if (d == null) {
          return CustomerWaitView(
              title: kRequestsTitle,
              error: _detailError,
              onBack: _toList,
              onRetry: () {
                setState(() => _detailError = null);
                unawaited(_loadDetail());
              });
        }
        return CustomerRequestView(
          detail: d,
          now: widget.now(),
          message: _message,
          connectedNow: widget.connectedNow,
          allowBusy: _allowBusy,
          sendBusy: _sendBusy,
          endBusy: _endBusy,
          upload: _upload,
          notice: _notice,
          noticeTone: _noticeTone,
          onBack: _toList,
          onAllow: _allow,
          onEndSession: _endSession,
          onSend: _sendMessage,
          onAttach: widget.pickFile == null || d.files == null || !d.row.open ? null : _attach,
          onDownload: widget.saveAs == null ? null : _download,
          onCancelRequest: _cancelRequest,
        );
      case _Page.list:
      case _Page.account:
        return CustomerListView(
          customer: customer,
          scope: _scope,
          rows: _rows,
          openCount: _openCount,
          error: _listError,
          now: widget.now(),
          onScope: _setScope,
          onOpen: (r) => _openRequest(r.id),
          onNew: _openCreate,
          onAccount: _account,
          onRetry: () {
            setState(() => _listError = null);
            unawaited(_loadList());
          },
          onBack: widget.onBack,
        );
    }
  }
}

/// DD-48 in C4.3: the screenshot shown before the request goes out with it (the DD-48 panel, without its own note).
class _ShotConfirm extends StatefulWidget {
  final Uint8List png;

  /// Null on success (the dialog closes and the request opens), otherwise the reason.
  final Future<String?> Function() onSend;
  final VoidCallback onClose;
  const _ShotConfirm({required this.png, required this.onSend, required this.onClose});

  @override
  State<_ShotConfirm> createState() => _ShotConfirmState();
}

class _ShotConfirmState extends State<_ShotConfirm> {
  final _note = TextEditingController();
  UploadPhase _phase = UploadPhase.ready;
  String _message = '';

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _phase = UploadPhase.sending;
      _message = '';
    });
    final error = await widget.onSend();
    if (!mounted) return;
    if (error == null) {
      widget.onClose();
      return;
    }
    setState(() {
      _phase = UploadPhase.failed;
      _message = error;
    });
  }

  @override
  Widget build(BuildContext context) => DolphinUploadPanel(
        kind: UploadKind.screenshot,
        phase: _phase,
        note: _note,
        png: widget.png,
        showNote: false,
        message: _message,
        onSend: _send,
        onClose: widget.onClose,
      );
}
