import 'dart:convert';

import 'api.dart';
import 'secret_box.dart';

/// TD-2: the last PC list, kept so the technician still sees (read-only) and can try the PCs while the portal is away.
/// Only what a tile shows: ID, Dolphin Connect ID, hostname, label, organization name and colour, tags, favourite. No
/// notes, customer names, phones or session details. Sealed like the token (DPAPI, this Windows user), cleared on
/// sign-out.
const kOfflineCacheVersion = 1;

/// A cache never grows past this many PCs.
const kOfflineCacheMax = 3000;

class CachedComputer {
  final String id;
  final String rustdeskId;
  final String? hostname;
  final String? label;
  final String orgName;
  final String orgColor;
  final List<String> tags;
  final bool favorite;
  const CachedComputer({
    required this.id,
    required this.rustdeskId,
    this.hostname,
    this.label,
    required this.orgName,
    required this.orgColor,
    this.tags = const [],
    this.favorite = false,
  });

  factory CachedComputer.of(Computer c) => CachedComputer(
        id: c.id,
        rustdeskId: c.rustdeskId,
        hostname: c.hostname,
        label: c.label,
        orgName: c.organization.name,
        orgColor: c.organization.color,
        tags: c.tags,
        favorite: c.favorite,
      );

  /// As a list row, marked [Computer.fromCache] (online unknown, no last-seen time, no session).
  Computer toComputer() => Computer(
        id: id,
        rustdeskId: rustdeskId,
        hostname: hostname,
        label: label,
        organization: OrgRef('', orgName, orgColor),
        tags: tags,
        favorite: favorite,
        fromCache: true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'rustdeskId': rustdeskId,
        'hostname': hostname,
        'label': label,
        'orgName': orgName,
        'orgColor': orgColor,
        'tags': tags,
        'favorite': favorite,
      };

  /// Null for a damaged entry (skipped, never a crash).
  static CachedComputer? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], rid = raw['rustdeskId'], org = raw['orgName'], color = raw['orgColor'];
    if (id is! String || rid is! String || org is! String || color is! String) return null;
    final h = raw['hostname'], l = raw['label'], t = raw['tags'], f = raw['favorite'];
    return CachedComputer(
      id: id,
      rustdeskId: rid,
      hostname: h is String ? h : null,
      label: l is String ? l : null,
      orgName: org,
      orgColor: color,
      tags: t is List ? List.unmodifiable(t.whereType<String>()) : const [],
      favorite: f == true,
    );
  }
}

class OfflineSnapshot {
  final List<CachedComputer> items;

  /// When the portal last gave this list: «آخرین وضعیت: ۱۰:۴۲».
  final DateTime lastUpdated;
  const OfflineSnapshot(this.items, this.lastUpdated);
}

/// The local, read-only filter of the cached list while offline: search over name, ID, organization and tags; the
/// favourite view; one tag. (Online / organization id / sort are the portal's; the cache keeps the portal's order.)
List<CachedComputer> filterCached(List<CachedComputer> items, ComputerQuery q) {
  final needle = q.q.trim().toLowerCase().replaceAll(' ', '');
  return items.where((c) {
    if (q.view == PcView.favorite && !c.favorite) return false;
    if ((q.tag ?? '').isNotEmpty && !c.tags.contains(q.tag)) return false;
    if (needle.isEmpty) return true;
    final hay = [c.label ?? '', c.hostname ?? '', c.rustdeskId, c.orgName, ...c.tags].join('|').toLowerCase();
    return hay.contains(needle) || c.rustdeskId.contains(needle);
  }).toList(growable: false);
}

class OfflineCache {
  final SecretBox _box;
  final DateTime Function() _now;
  OfflineCache(this._box, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Replaces the cached list with [rows] (the first page of the unfiltered list).
  Future<void> save(List<Computer> rows) => _write(rows.map(CachedComputer.of).toList());

  /// Adds a following page; PCs already cached are replaced in place.
  Future<void> append(List<Computer> rows) async {
    final current = await load();
    final items = [...?current?.items];
    final index = {for (var i = 0; i < items.length; i++) items[i].id: i};
    for (final r in rows) {
      final c = CachedComputer.of(r);
      final at = index[c.id];
      if (at != null) {
        items[at] = c;
      } else {
        index[c.id] = items.length;
        items.add(c);
      }
    }
    await _write(items);
  }

  /// Keeps the cached star in step with a change the technician made.
  Future<void> setFavorite(String id, bool on) async {
    final current = await load();
    if (current == null) return;
    final items = [
      for (final c in current.items)
        c.id == id
            ? CachedComputer(
                id: c.id,
                rustdeskId: c.rustdeskId,
                hostname: c.hostname,
                label: c.label,
                orgName: c.orgName,
                orgColor: c.orgColor,
                tags: c.tags,
                favorite: on)
            : c
    ];
    await _box.write(jsonEncode({
      'v': kOfflineCacheVersion,
      'lastUpdated': current.lastUpdated.toUtc().toIso8601String(),
      'items': items.map((c) => c.toJson()).toList(),
    }));
  }

  Future<void> _write(List<CachedComputer> items) => _box.write(jsonEncode({
        'v': kOfflineCacheVersion,
        'lastUpdated': _now().toUtc().toIso8601String(),
        'items': items.take(kOfflineCacheMax).map((c) => c.toJson()).toList(),
      }));

  /// The cached list, or null when there is none (never saved, cleared, another version, damaged).
  Future<OfflineSnapshot?> load() async {
    final raw = await _box.read();
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map || data['v'] != kOfflineCacheVersion) return null;
      final at = DateTime.tryParse(data['lastUpdated'] is String ? data['lastUpdated'] as String : '');
      final list = data['items'];
      if (at == null || list is! List) return null;
      return OfflineSnapshot(
          List.unmodifiable(list.map(CachedComputer.tryParse).whereType<CachedComputer>()), at.toLocal());
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() => _box.clear();
}
