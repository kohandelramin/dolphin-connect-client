import 'dart:async';

import 'api.dart';
import 'cache.dart';

/// Plan 19: what the technician screens read, over [ApiClient], with the offline PC list (TD-2) kept in step and the
/// rarely changing lists (snippets, config) held in memory. No widgets.
class TechRepository {
  final ApiClient api;
  final OfflineCache cache;
  TechRepository(this.api, this.cache);

  AppConfig? _config;
  List<Snippet>? _snippets;

  /// The last config read, or null before the first.
  AppConfig? get config => _config;

  // -- computers

  /// One page of «رایانه‌ها». Pages of the unfiltered list also refresh the offline cache (the first page replaces
  /// it, later pages are added).
  Future<ComputerPage> computers(ComputerQuery query, {String? cursor}) async {
    final page = await api.computers(query, cursor: cursor);
    if (query.isUnfiltered) {
      try {
        if (cursor == null) {
          await cache.save(page.rows);
        } else {
          await cache.append(page.rows);
        }
      } catch (_) {
        // A cache that cannot be written only means no offline list; the online list still shows.
      }
    }
    return page;
  }

  /// The cached list, filtered locally by [query] (search, favourites, tag), or null when there is none.
  Future<OfflineSnapshot?> offlineComputers([ComputerQuery query = const ComputerQuery()]) async {
    final snap = await cache.load();
    if (snap == null) return null;
    return OfflineSnapshot(filterCached(snap.items, query), snap.lastUpdated);
  }

  Future<ComputerDetail> computer(String id) => api.computer(id);

  /// Saves the star on the portal, then in the offline cache. Returns the state the portal saved.
  Future<bool> setFavorite(String id, bool on) async {
    final saved = await api.setFavorite(id, on);
    try {
      await cache.setFavorite(id, saved);
    } catch (_) {}
    return saved;
  }

  // -- requests, organizations, history

  Future<RequestPage> requests(RequestScope scope, {String? cursor}) => api.requests(scope, cursor: cursor);
  Future<void> takeRequest(String id) => api.takeRequest(id);
  Future<OrganizationPage> organizations({String q = '', String? cursor}) => api.organizations(q: q, cursor: cursor);
  Future<OrganizationDetail> organization(String id) => api.organization(id);
  Future<List<HistoryEntry>> deviceHistory(String deviceId) => api.history(deviceId: deviceId);
  Future<List<HistoryEntry>> organizationHistory(String organizationId) => api.history(organizationId: organizationId);

  // -- snippets, config

  /// The active ready-made texts; read once per sign-in unless [refresh].
  Future<List<Snippet>> snippets({bool refresh = false}) async {
    if (!refresh && _snippets != null) return _snippets!;
    return _snippets = await api.snippets();
  }

  /// GET /config: switches, theme overrides (untouched), latest technician build, call reasons.
  Future<AppConfig> loadConfig() async => _config = await api.config();

  /// Forgets what is held in memory (sign-out). The offline cache is cleared by the session store.
  void reset() {
    _config = null;
    _snippets = null;
  }
}

/// Waits until calls stop for [delay], then runs the last one: the search field asks the portal once the technician
/// pauses typing, not on every key.
class Debouncer {
  final Duration delay;
  Timer? _timer;
  Debouncer([this.delay = const Duration(milliseconds: 350)]);

  void call(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  bool get pending => _timer?.isActive ?? false;

  void cancel() => _timer?.cancel();
}
