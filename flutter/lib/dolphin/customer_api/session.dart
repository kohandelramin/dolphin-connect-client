import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../tech/secret_box.dart';
import 'api.dart';

/// Plan 19 C4: the customer's sign-in in the customer app (ADR-0008: username and password only). The token is the
/// same portal session as the web's `dc_session`; it is kept in a DPAPI-sealed file for this Windows user
/// ([openCustomerBox]), handed to the API client through [ApiTransport.token], and never logged, shown or put in a URL.
/// The password is never kept at all.
///
/// «خروج» calls `/logout` and deletes the sealed file; a 401 `expired` deletes it too and shows the sign-in again.

/// The sealed file of the customer's sign-in, in its own folder and with its own DPAPI entropy ("dc-cust-v1").
const kCustomerBoxFolder = 'customer';
const kCustomerBoxName = 'session.bin';
const kCustomerBoxEntropy = [100, 99, 45, 99, 117, 115, 116, 45, 118, 49];

Future<SecretBox> openCustomerBox() => openSealedBox(kCustomerBoxFolder, kCustomerBoxName, entropy: kCustomerBoxEntropy);

const kMsgFillSignIn = 'نام کاربری و رمز را وارد کنید.';
const kMsgPasswordMismatch = 'رمز تازه و تکرارش یکی نیستند.';
const kMsgPasswordSame = 'رمز تازه باید با رمز فعلی فرق داشته باشد.';
const kMsgPasswordFill = 'رمز فعلی و رمز تازه را وارد کنید.';
const kMsgPasswordChanged = 'رمز عوض شد.';

class StoredCustomer {
  final String token;
  final DateTime expiresAt;
  final bool mustChangePassword;
  final CustomerInfo customer;
  const StoredCustomer(this.token, this.expiresAt, this.mustChangePassword, this.customer);

  bool expiredAt(DateTime now) => !expiresAt.isAfter(now);

  StoredCustomer copyWith({bool? mustChangePassword, CustomerInfo? customer}) =>
      StoredCustomer(token, expiresAt, mustChangePassword ?? this.mustChangePassword, customer ?? this.customer);

  String toJson() => jsonEncode({
        'token': token,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'mustChangePassword': mustChangePassword,
        'customer': customer.toJson(),
      });

  static StoredCustomer? tryParse(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map<String, dynamic>) return null;
      final t = m['token'], e = m['expiresAt'], c = m['customer'];
      if (t is! String || t.isEmpty || e is! String || c is! Map<String, dynamic>) return null;
      final at = DateTime.tryParse(e);
      if (at == null) return null;
      return StoredCustomer(t, at, m['mustChangePassword'] == true, CustomerInfo.fromJson(c));
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'StoredCustomer(${customer.id})'; // never the token
}

enum CustomerSignIn {
  /// Not read from disk yet.
  unknown,
  signedOut,
  signedIn,

  /// The portal said the sign-in is over (or it passed its expiry): the sign-in form says so.
  expired,
}

class CustomerSession extends ChangeNotifier {
  final CustomerApi api;
  final SecretBox _box;
  final DateTime Function() _now;
  final List<StreamSubscription<void>> _subs = [];

  CustomerSession(this.api, this._box, {DateTime Function()? now}) : _now = now ?? DateTime.now {
    api.token = () => _stored?.token;
    _subs.add(api.signInExpired.listen((_) => expire()));
    _subs.add(api.passwordChangeNeeded.listen((_) => _needPasswordChange()));
  }

  StoredCustomer? _stored;
  CustomerSignIn _state = CustomerSignIn.unknown;
  bool _busy = false;
  String? _error;

  CustomerSignIn get state => _state;
  bool get signedIn => _state == CustomerSignIn.signedIn;
  CustomerInfo? get customer => _stored?.customer;

  /// UN-10: the first sign-in (or a reset) must change the password before anything else.
  bool get mustChangePassword => _stored?.mustChangePassword ?? false;

  /// Signed in and free to use the requests: the unread count is asked for only then.
  bool get ready => signedIn && !mustChangePassword;

  bool get busy => _busy;

  /// The portal's answer to the last password change («رمز عوض شد.»), null before one.
  String? lastPasswordMessage;

  /// The last sign-in error in Persian, null after success.
  String? get error => _error;

  /// Reads the stored sign-in at start-up; one past its expiry is dropped as expired. Then asks `/me` once, quietly,
  /// for the name and whether the password must change (offline keeps what was stored).
  Future<void> load() async {
    final raw = await _box.read();
    final s = raw == null ? null : StoredCustomer.tryParse(raw);
    if (s == null) {
      if (raw != null) await _box.clear();
      _set(null, CustomerSignIn.signedOut);
      return;
    }
    if (s.expiredAt(_now())) {
      await _box.clear();
      _set(null, CustomerSignIn.expired);
      return;
    }
    _set(s, CustomerSignIn.signedIn);
    unawaited(refresh());
  }

  /// GET /me: the stored name and the password flag brought up to date.
  Future<void> refresh() async {
    final s = _stored;
    if (s == null) return;
    try {
      final me = await api.me();
      if (!identical(_stored, s)) return; // signed out meanwhile
      await _keep(s.copyWith(mustChangePassword: me.mustChangePassword, customer: me.customer));
    } catch (_) {
      // Offline or expired: the expiry stream handles the latter.
    }
  }

  /// POST /customer/login, then keeps the token. Returns true on success; otherwise [error] says why.
  Future<bool> signIn(String username, String password) async {
    if (_busy) return false;
    if (username.trim().isEmpty || password.isEmpty) {
      _error = kMsgFillSignIn;
      notifyListeners();
      return false;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final r = await api.login(username, password);
      final s = StoredCustomer(r.token, r.expiresAt, r.mustChangePassword, r.customer);
      await _box.write(s.toJson());
      _busy = false;
      _set(s, CustomerSignIn.signedIn);
      return true;
    } catch (e) {
      _error = apiErrorText(e);
    }
    _busy = false;
    notifyListeners();
    return false;
  }

  /// POST /customer/password. Returns null on success (the portal's own words in [lastPasswordMessage]), otherwise the
  /// Persian reason. The checks the web form makes
  /// before sending are made here too.
  Future<String?> changePassword(String current, String next, String confirm) async {
    if (current.isEmpty || next.isEmpty) return kMsgPasswordFill;
    if (next != confirm) return kMsgPasswordMismatch;
    if (next == current) return kMsgPasswordSame;
    try {
      lastPasswordMessage = await api.changePassword(current, next);
    } catch (e) {
      return apiErrorText(e);
    }
    final s = _stored;
    if (s != null && s.mustChangePassword) await _keep(s.copyWith(mustChangePassword: false));
    return null;
  }

  /// «خروج از این رایانه»: ends the session on the portal (best effort: offline, the token still dies at its expiry)
  /// and deletes the sealed token here.
  Future<void> signOut() async {
    if (_stored != null) {
      try {
        await api.logout();
      } catch (_) {}
    }
    await _box.clear();
    _set(null, CustomerSignIn.signedOut);
  }

  /// The portal answered 401 `expired`: delete the token, show the sign-in screen.
  Future<void> expire() async {
    if (_stored == null && _state != CustomerSignIn.signedIn) return;
    await _box.clear();
    _set(null, CustomerSignIn.expired);
  }

  Future<void> _needPasswordChange() async {
    final s = _stored;
    if (s == null || s.mustChangePassword) return;
    await _keep(s.copyWith(mustChangePassword: true));
  }

  Future<void> _keep(StoredCustomer s) async {
    await _box.write(s.toJson());
    _set(s, _state);
  }

  void _set(StoredCustomer? s, CustomerSignIn state) {
    _stored = s;
    _state = state;
    if (s != null) _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

/// C4.6: the unread count is asked this often.
const kUnreadEvery = Duration(seconds: 30);

/// C4.6: the number of requests with a new staff message, for the main window's row. Asked every [every] (30 s), only
/// while [CustomerSession.ready]; signing out (or an expiry) stops the timer and puts the count back to 0.
class UnreadPoller {
  final CustomerSession session;
  final Duration every;
  final ValueNotifier<int> count = ValueNotifier(0);
  Timer? _timer;
  bool _disposed = false;

  UnreadPoller(this.session, {this.every = kUnreadEvery}) {
    session.addListener(_follow);
    _follow();
  }

  bool get running => _timer != null;

  void _follow() {
    if (_disposed) return;
    if (session.ready) {
      if (_timer == null) {
        _timer = Timer.periodic(every, (_) => poll());
        poll();
      }
    } else {
      _timer?.cancel();
      _timer = null;
      count.value = 0;
    }
  }

  /// One read now (also after the customer viewed a request). Failures keep the last count.
  Future<void> poll() async {
    if (!session.ready) return;
    try {
      final n = await session.api.unread();
      if (!_disposed && session.ready) count.value = n < 0 ? 0 : n;
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    session.removeListener(_follow);
    count.dispose();
  }
}
