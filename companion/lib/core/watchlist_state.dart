import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum WatchlistMatchType {
  oui('OUI'),
  fullMac('MAC'),
  name('NAME'),
  serviceUuid('UUID');

  const WatchlistMatchType(this.label);
  final String label;
}

class WatchlistEntry {
  WatchlistEntry({
    required this.identifier,
    this.matchType = WatchlistMatchType.oui,
    this.description = '',
    this.enabled = true,
  });

  String identifier;
  WatchlistMatchType matchType;
  String description;
  bool enabled;

  bool get isFullMac => matchType == WatchlistMatchType.fullMac;
  bool get isName => matchType == WatchlistMatchType.name;
  bool get isOui => matchType == WatchlistMatchType.oui;
  bool get isServiceUuid => matchType == WatchlistMatchType.serviceUuid;

  Map<String, dynamic> toJson() => {
        'identifier': identifier,
        'matchType': matchType.name,
        'description': description,
        'enabled': enabled,
      };

  factory WatchlistEntry.fromJson(Map<String, dynamic> json) {
    final raw = json['matchType'];
    WatchlistMatchType type;
    if (raw is String) {
      type = WatchlistMatchType.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => WatchlistMatchType.oui,
      );
    } else if (json['isFullMac'] == true) {
      type = WatchlistMatchType.fullMac;
    } else {
      type = WatchlistMatchType.oui;
    }
    return WatchlistEntry(
      identifier: json['identifier'] as String? ?? '',
      matchType: type,
      description: json['description'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

class WatchlistState extends ChangeNotifier {
  WatchlistState() {
    _loadFuture = _load();
  }

  static const _prefsKey = 'watchlist_entries_v1';

  final List<WatchlistEntry> entries = [];
  bool _loaded = false;
  late final Future<void> _loadFuture;
  bool get isLoaded => _loaded;

  List<WatchlistEntry> get enabledEntries =>
      entries.where((e) => e.enabled).toList();

  Future<void> toggleEnabled(WatchlistEntry entry, {required bool enabled}) async {
    await _loadFuture;
    final idx = entries.indexOf(entry);
    if (idx == -1) return;
    entries[idx].enabled = enabled;
    notifyListeners();
    await _save();
  }

  Future<void> add(WatchlistEntry entry) async {
    await _loadFuture;
    entries.add(entry);
    notifyListeners();
    await _save();
  }

  Future<void> remove(WatchlistEntry entry) async {
    await _loadFuture;
    entries.remove(entry);
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    await _loadFuture;
    entries.clear();
    notifyListeners();
    await _save();
  }

  Future<void> replaceAll(Iterable<WatchlistEntry> next) async {
    await _loadFuture;
    entries
      ..clear()
      ..addAll(next);
    notifyListeners();
    await _save();
  }

  Future<void> _load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && entries.isEmpty) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        entries
          ..clear()
          ..addAll(list.map(WatchlistEntry.fromJson));
      } catch (_) {
        entries.clear();
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await _writeRaw(prefs);
  }

  Future<void> _writeRaw(SharedPreferences prefs) async {
    final json = jsonEncode(entries.map((e) => e.toJson()).toList());
    await prefs.setString(_prefsKey, json);
  }
}

final watchlistProvider = ChangeNotifierProvider<WatchlistState>((ref) {
  return WatchlistState();
});
