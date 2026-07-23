import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/core/wdgwars/wdgwars_api.dart';

/// Manages WDGWars credentials, API calls, and per-session upload state.
class WdgwarsProvider extends ChangeNotifier {
  WdgwarsProvider(this._prefs) {
    _uploadedSessions.addAll(_prefs.getStringList(_keyUploaded) ?? const []);
    _loadCredentials();
  }

  final SharedPreferences _prefs;
  static const _storage = FlutterSecureStorage();
  static const _keyApiKey = 'wdgwars_api_key';
  static const _keyUploaded = 'wdgwars_uploaded_sessions';

  WdgwarsApi? _api;
  String _apiKey = '';
  bool _isLoggedIn = false;
  bool _isLoading = false;
  WdgwarsUserStats? _stats;
  String? _error;
  final Set<String> _uploadedSessions = {};
  final Map<String, bool> _uploadingMap = {};

  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  WdgwarsUserStats? get stats => _stats;
  String? get error => _error;

  bool isUploaded(String sessionId) => _uploadedSessions.contains(sessionId);
  bool isUploading(String sessionId) => _uploadingMap[sessionId] == true;

  Future<void> _loadCredentials() async {
    _apiKey = await _storage.read(key: _keyApiKey) ?? '';
    if (_apiKey.isNotEmpty) {
      _api = WdgwarsApi(apiKey: _apiKey);
      _isLoggedIn = true;
      notifyListeners();
      refreshStats();
    }
  }

  /// Validate and store a WDGWars API key.
  Future<bool> login(String apiKey) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final api = WdgwarsApi(apiKey: apiKey);
      final stats = await api.getUserStats();
      _api?.dispose();
      _api = api;
      _apiKey = apiKey;
      _stats = stats;
      _isLoggedIn = true;
      await _storage.write(key: _keyApiKey, value: apiKey);
      DebugLog.log('WDGWARS: linked as ${stats.username} (${stats.total} total)');
    } on WdgwarsApiException catch (e) {
      _error = e.message;
      _isLoggedIn = false;
      DebugLog.log('WDGWARS: login failed: $e');
    } catch (e) {
      _error = 'Connection failed: $e';
      _isLoggedIn = false;
      DebugLog.log('WDGWARS: login error: $e');
    }

    _isLoading = false;
    notifyListeners();
    return _isLoggedIn;
  }

  Future<void> logout() async {
    _api?.dispose();
    _api = null;
    _apiKey = '';
    _isLoggedIn = false;
    _stats = null;
    await _storage.delete(key: _keyApiKey);
    notifyListeners();
    DebugLog.log('WDGWARS: unlinked');
  }

  Future<void> refreshStats() async {
    if (_api == null) return;
    try {
      _stats = await _api!.getUserStats();
      notifyListeners();
    } catch (e) {
      DebugLog.log('WDGWARS: stats refresh failed: $e');
    }
  }

  /// Upload a session CSV to WDGWars.
  Future<WdgwarsUploadResult?> uploadSession(
    String sessionId,
    WardriveController wd,
  ) async {
    if (_api == null || _uploadedSessions.contains(sessionId)) return null;

    _error = null;
    _uploadingMap[sessionId] = true;
    notifyListeners();

    var sent = 0;
    var total = 0;
    try {
      final file = await wd.getCsvFile(sessionId);
      if (file == null) {
        _error = 'No CSV data for this session';
        _uploadingMap.remove(sessionId);
        notifyListeners();
        return null;
      }

      final result = await _api!.uploadCsv(file, onProgress: (s, t) {
        sent = s;
        total = t;
      });

      _error = null;
      _uploadedSessions.add(sessionId);
      _prefs.setStringList(_keyUploaded, _uploadedSessions.toList());
      refreshStats();

      DebugLog.log('WDGWARS: uploaded $sessionId ($total B) — ${result.summary}');
      _uploadingMap.remove(sessionId);
      notifyListeners();
      return result;
    } on WdgwarsApiException catch (e) {
      _error = e.message;
      DebugLog.log('WDGWARS: upload failed at $sent/$total B: ${e.message}');
    } catch (e) {
      _error = e.toString();
      DebugLog.log('WDGWARS: upload error at $sent/$total B: '
          '${e.runtimeType} $e');
    }

    _uploadingMap.remove(sessionId);
    notifyListeners();
    return null;
  }
}

final wdgwarsProvider = ChangeNotifierProvider<WdgwarsProvider>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return WdgwarsProvider(prefs);
});
