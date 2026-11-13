import 'package:flutter/foundation.dart';

import '../tech/api.dart';
import '../tech/repository.dart';
import '../tech/state.dart';

/// Plan 19: the smaller sections' state (سازمان‌ها، تاریخچه، متن‌های آماده), over [TechRepository]. Read only: the
/// organizations' admin pages stay on the portal (opened in the browser).

class OrganizationsController extends ChangeNotifier {
  final TechRepository repo;
  final ConnectionController connection;
  final Debouncer _debounce;
  OrganizationsController(this.repo, this.connection, {Duration debounce = const Duration(milliseconds: 350)})
      : _debounce = Debouncer(debounce);

  String _q = '';
  List<OrganizationRow> _rows = const [];
  String? _next;
  bool _loading = false;
  String? _error;
  OrganizationDetail? _detail;
  bool _detailLoading = false;
  int _gen = 0;
  bool _disposed = false;

  String get query => _q;
  List<OrganizationRow> get rows => _rows;
  bool get hasMore => _next != null;
  bool get loading => _loading;
  String? get error => _error;
  OrganizationDetail? get detail => _detail;
  bool get detailLoading => _detailLoading;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    _debounce.cancel();
    final gen = ++_gen;
    _loading = true;
    _changed();
    try {
      final page = await connection.track(() => repo.organizations(q: _q));
      if (gen != _gen) return;
      _rows = page.rows;
      _next = page.next;
      _error = null;
    } catch (e) {
      if (gen == _gen) _error = errorText(e);
    } finally {
      if (gen == _gen) {
        _loading = false;
        _changed();
      }
    }
  }

  Future<void> loadMore() async {
    final cursor = _next;
    if (cursor == null || _loading) return;
    final gen = _gen;
    try {
      final page = await connection.track(() => repo.organizations(q: _q, cursor: cursor));
      if (gen != _gen) return;
      _rows = [..._rows, ...page.rows];
      _next = page.next;
    } catch (e) {
      _error = errorText(e);
    }
    _changed();
  }

  void search(String q) {
    if (q == _q) return;
    _q = q;
    _debounce(load);
  }

  Future<void> open(String id) async {
    _detailLoading = true;
    _detail = null;
    _changed();
    try {
      _detail = await connection.track(() => repo.organization(id));
      _error = null;
    } catch (e) {
      _error = errorText(e);
    } finally {
      _detailLoading = false;
      _changed();
    }
  }

  void closeDetail() {
    _detail = null;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce.cancel();
    super.dispose();
  }
}

/// «تاریخچه»: the last contacts of one organization (the API answers per PC or per organization).
class HistoryController extends ChangeNotifier {
  final TechRepository repo;
  final ConnectionController connection;
  HistoryController(this.repo, this.connection);

  OrganizationRow? _org;
  List<HistoryEntry> _rows = const [];
  bool _loading = false;
  String? _error;
  int _gen = 0;
  bool _disposed = false;

  OrganizationRow? get organization => _org;
  List<HistoryEntry> get rows => _rows;
  bool get loading => _loading;
  String? get error => _error;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> show(OrganizationRow org) async {
    _org = org;
    final gen = ++_gen;
    _loading = true;
    _rows = const [];
    _changed();
    try {
      final rows = await connection.track(() => repo.organizationHistory(org.id));
      if (gen != _gen) return;
      _rows = rows;
      _error = null;
    } catch (e) {
      if (gen == _gen) _error = errorText(e);
    } finally {
      if (gen == _gen) {
        _loading = false;
        _changed();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// «متن‌های آماده»: read once per sign-in (the repository keeps them), refreshed on demand.
class SnippetsController extends ChangeNotifier {
  final TechRepository repo;
  final ConnectionController connection;
  SnippetsController(this.repo, this.connection);

  List<Snippet> _rows = const [];
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  bool _disposed = false;

  List<Snippet> get rows => _rows;
  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;

  Future<void> load({bool refresh = false}) async {
    _loading = true;
    if (!_disposed) notifyListeners();
    try {
      _rows = await connection.track(() => repo.snippets(refresh: refresh));
      _loaded = true;
      _error = null;
    } catch (e) {
      _error = errorText(e);
    } finally {
      _loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
