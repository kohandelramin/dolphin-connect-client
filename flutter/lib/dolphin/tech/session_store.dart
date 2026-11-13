import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'cache.dart';
import 'secret_box.dart';

/// Plan 19: the technician's sign-in (ADR-0008: username and password only). The token is a staff session on the
/// portal (8 h); it is kept in a DPAPI-sealed file for this Windows user ([SealedFileBox]), handed to the API client
/// through [ApiClient.token], and never logged, shown or put in a URL. The password is never kept at all.
///
/// Sign-out (or an expired sign-in) forgets the token and clears the offline PC list (TD-2).
class StoredSession {
  final String token;
  final DateTime expiresAt;
  final StaffInfo staff;
  const StoredSession(this.token, this.expiresAt, this.staff);

  bool expiredAt(DateTime now) => !expiresAt.isAfter(now);

  String toJson() =>
      jsonEncode({'token': token, 'expiresAt': expiresAt.toUtc().toIso8601String(), 'staff': staff.toJson()});

  static StoredSession? tryParse(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map<String, dynamic>) return null;
      final t = m['token'], e = m['expiresAt'], s = m['staff'];
      if (t is! String || t.isEmpty || e is! String || s is! Map<String, dynamic>) return null;
      final at = DateTime.tryParse(e);
      if (at == null) return null;
      return StoredSession(t, at, StaffInfo.fromJson(s));
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'StoredSession(${staff.name})'; // never the token
}

enum SignInState {
  /// Not read from disk yet.
  unknown,
  signedOut,
  signedIn,

  /// The portal said the sign-in is over (or it passed its expiry): show «ورود منقضی شد» and the sign-in form.
  expired,
}

class SessionStore extends ChangeNotifier {
  final ApiClient api;
  final SecretBox _box;
  final OfflineCache? _cache;
  final DateTime Function() _now;
  StreamSubscription<SignInExpired>? _sub;

  SessionStore(this.api, this._box, {OfflineCache? cache, DateTime Function()? now})
      : _cache = cache,
        _now = now ?? DateTime.now {
    api.token = () => _session?.token;
    _sub = api.signInExpired.listen((_) => expire());
  }

  StoredSession? _session;
  SignInState _state = SignInState.unknown;
  bool _busy = false;
  String? _error;

  SignInState get state => _state;
  bool get signedIn => _state == SignInState.signedIn;
  StaffInfo? get staff => _session?.staff;
  DateTime? get expiresAt => _session?.expiresAt;

  /// A sign-in is running (the form disables its button).
  bool get busy => _busy;

  /// The last sign-in error in Persian (wrong password, too many tries, portal away), null after success.
  String? get error => _error;

  /// Reads the stored session at start-up. A session past its expiry is dropped as expired.
  Future<void> load() async {
    final raw = await _box.read();
    final s = raw == null ? null : StoredSession.tryParse(raw);
    if (s == null) {
      if (raw != null) await _box.clear();
      _set(null, SignInState.signedOut);
      return;
    }
    if (s.expiredAt(_now())) {
      await _forget();
      _set(null, SignInState.expired);
      return;
    }
    _set(s, SignInState.signedIn);
  }

  /// POST /login, then keeps the token. Returns true on success; otherwise [error] says why.
  Future<bool> signIn(String username, String password) async {
    if (_busy) return false;
    if (username.trim().isEmpty || password.isEmpty) {
      _error = 'نام کاربری و رمز عبور را وارد کنید.';
      notifyListeners();
      return false;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final r = await api.login(username, password);
      final s = StoredSession(r.token, r.expiresAt, r.staff);
      await _box.write(s.toJson());
      _busy = false;
      _set(s, SignInState.signedIn);
      return true;
    } on ApiError catch (e) {
      _error = e.message;
    } on PortalUnreachable catch (e) {
      _error = e.message;
    } catch (_) {
      _error = kMsgServer;
    }
    _busy = false;
    notifyListeners();
    return false;
  }

  /// «خروج»: ends the session on the portal (best effort: offline, the token still dies at its expiry), forgets it
  /// here and clears the offline list.
  Future<void> signOut() async {
    if (_session != null) {
      try {
        await api.logout();
      } catch (_) {}
    }
    await _forget();
    _set(null, SignInState.signedOut);
  }

  /// The portal answered 401 `expired`: forget the token and the offline list, show the sign-in screen.
  Future<void> expire() async {
    if (_session == null && _state != SignInState.signedIn) return;
    await _forget();
    _set(null, SignInState.expired);
  }

  /// The staff info with a newly registered Dolphin Connect ID, kept for the next start.
  Future<void> updateRustdeskId(String rustdeskId) async {
    final s = _session;
    if (s == null) return;
    final next = StoredSession(
        s.token, s.expiresAt, StaffInfo(id: s.staff.id, name: s.staff.name, role: s.staff.role, rustdeskId: rustdeskId));
    await _box.write(next.toJson());
    _set(next, _state);
  }

  Future<void> _forget() async {
    await _box.clear();
    await _cache?.clear();
  }

  void _set(StoredSession? s, SignInState state) {
    _session = s;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
