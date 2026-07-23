import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

class WdgwarsApi {
  WdgwarsApi({required String apiKey})
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://wdgwars.pl',
          headers: {'X-API-Key': apiKey},
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (s) => s != null && s < 500,
        ));

  final Dio _dio;

  /// Validate the API key and fetch the account's stats (GET /api/me).
  Future<WdgwarsUserStats> getUserStats() async {
    final resp = await _dio.get('/api/me');
    final data = _asMap(resp.data);
    if (resp.statusCode == 401 || data['ok'] == false) {
      throw WdgwarsApiException(
          (data['error'] as String?) ?? 'Invalid API key');
    }
    if (resp.statusCode != 200) {
      throw WdgwarsApiException('HTTP ${resp.statusCode}');
    }
    return WdgwarsUserStats.fromJson(data);
  }

  /// Upload a WigleWifi-1.6 CSV via the simple multipart endpoint.
  Future<WdgwarsUploadResult> uploadCsv(
    File csvFile, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final bytes = await csvFile.length();
    if (bytes == 0) throw WdgwarsApiException('CSV is empty — nothing to upload');

    Response<dynamic>? resp;
    Object? lastTransportError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        resp = await _postCsv(csvFile, bytes, onProgress);
        break;
      } on DioException catch (e) {
        if (!_isTransient(e)) throw WdgwarsApiException(_dioMessage(e));
        lastTransportError = e.error ?? e;
        if (attempt == 2) break;
        // The TLS session itself is the casualty — never retry on the same one.
        _resetConnection();
        await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    if (resp == null) {
      throw WdgwarsApiException(_transportMessage(lastTransportError));
    }

    final code = resp.statusCode ?? 0;
    final data = _asMap(resp.data);
    if (code == 401) {
      throw WdgwarsApiException(
          (data['error'] as String?) ?? 'Invalid API key');
    }
    if (code == 413) {
      throw WdgwarsApiException('File too large (max 30 MB) — split the session');
    }
    if (code == 429) {
      final retry = resp.headers.value('retry-after');
      final wait = retry != null ? ' — retry in ${retry}s' : ' — try again shortly';
      throw WdgwarsApiException('Rate limited (120/min)$wait');
    }
    if (code == 202 || (code >= 200 && code < 300 && data['ok'] != false)) {
      return WdgwarsUploadResult.fromJson(data);
    }
    throw WdgwarsApiException(
        (data['error'] as String?) ?? 'Upload failed (HTTP $code)');
  }

  Future<Response<dynamic>> _postCsv(
    File csvFile,
    int bytes,
    void Function(int sent, int total)? onProgress,
  ) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        csvFile.path,
        filename: csvFile.uri.pathSegments.last,
        contentType: DioMediaType('text', 'csv'),
      ),
    });

    return _dio.post(
      '/api/upload-csv',
      data: formData,
      onSendProgress: onProgress,
      options: Options(
        sendTimeout: _sendTimeoutFor(bytes),
        receiveTimeout: const Duration(seconds: 180),
      ),
    );
  }

  /// dio applies sendTimeout to the whole body transfer, not per-chunk, so it
  /// has to scale with size: 60s of headroom + 12s per MB (~700 kbit/s floor).
  static Duration _sendTimeoutFor(int bytes) {
    final mb = bytes / (1024 * 1024);
    final secs = 60 + (mb * 12).ceil();
    return Duration(seconds: secs.clamp(60, 900));
  }

  static bool _isTransient(DioException e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return true;
    }
    final inner = e.error;
    return inner is TlsException ||
        inner is HandshakeException ||
        inner is SocketException ||
        inner is HttpException;
  }

  static String _dioMessage(DioException e) {
    final data = _asMap(e.response?.data);
    final serverMsg = data['error'] as String?;
    if (serverMsg != null && serverMsg.isNotEmpty) return serverMsg;
    final code = e.response?.statusCode;
    if (code != null) return 'Server rejected the upload (HTTP $code)';
    return e.message ?? 'Upload failed (${e.type.name})';
  }

  static String _transportMessage(Object? err) {
    if (err is TlsException) {
      return 'Connection corrupted mid-upload (TLS) — retried 3x. '
          'Switch between WiFi and cellular, or split the session.';
    }
    return 'Network error during upload — retried 3x. Try again on a better link.';
  }

  void _resetConnection() {
    _dio.httpClientAdapter.close(force: true);
    _dio.httpClientAdapter = IOHttpClientAdapter();
  }

  static Map<String, dynamic> _asMap(dynamic raw) =>
      raw is Map<String, dynamic> ? raw : <String, dynamic>{};

  void dispose() => _dio.close();
}

class WdgwarsApiException implements Exception {
  WdgwarsApiException(this.message);
  final String message;

  @override
  String toString() => 'WdgwarsApiException: $message';
}

class WdgwarsUserStats {
  WdgwarsUserStats({
    required this.username,
    required this.wifi,
    required this.ble,
    required this.aircraft,
    required this.mesh,
    required this.total,
    required this.badges,
    required this.gang,
    required this.rank,
    required this.dailyUsed,
    required this.dailyRemaining,
    required this.dailyCap,
  });

  final String username;
  final int wifi;
  final int ble;
  final int aircraft;
  final int mesh;
  final int total;
  final List<String> badges;
  final String gang;

  /// All-time leaderboard rank; null when unranked.
  final int? rank;

  /// 24h-rolling new-AP quota (server-enforced 500k/day cap).
  final int dailyUsed;
  final int dailyRemaining;
  final int dailyCap;

  factory WdgwarsUserStats.fromJson(Map<String, dynamic> json) {
    final rankMap = json['your_rank'];
    final limitMap = json['new_ap_limit'];
    int? asInt(dynamic v) => v is num ? v.toInt() : null;
    return WdgwarsUserStats(
      username: (json['username'] as String?) ?? '',
      wifi: asInt(json['wifi']) ?? 0,
      ble: asInt(json['ble']) ?? 0,
      aircraft: asInt(json['aircraft']) ?? 0,
      mesh: asInt(json['mesh']) ?? 0,
      total: asInt(json['total']) ?? 0,
      badges: (json['badges'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      gang: (json['gang'] as String?) ?? '',
      rank: rankMap is Map ? asInt(rankMap['all_time']) : null,
      dailyUsed: limitMap is Map ? (asInt(limitMap['used']) ?? 0) : 0,
      dailyRemaining: limitMap is Map ? (asInt(limitMap['remaining']) ?? 0) : 0,
      dailyCap: limitMap is Map ? (asInt(limitMap['cap']) ?? 0) : 0,
    );
  }
}

class WdgwarsUploadResult {
  WdgwarsUploadResult({
    required this.accepted,
    required this.newNetworks,
    required this.mergedSamples,
    required this.async,
    required this.jobId,
  });

  final int? accepted;
  final int? newNetworks;
  final int? mergedSamples;
  final bool async;
  final String? jobId;

  String get summary {
    if (async) return 'Queued for WDGWars processing';
    final parts = <String>[];
    if (accepted != null) parts.add('$accepted records');
    if (newNetworks != null) parts.add('$newNetworks new');
    if (mergedSamples != null) parts.add('$mergedSamples merged');
    return parts.isEmpty ? 'Uploaded to WDGWars' : parts.join(' · ');
  }

  factory WdgwarsUploadResult.fromJson(Map<String, dynamic> json) {
    int? pick(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v is num) return v.toInt();
      }
      return null;
    }

    final jobId = json['job_id']?.toString();
    return WdgwarsUploadResult(
      accepted: pick(['accepted', 'networks', 'total', 'count']),
      newNetworks: pick(['new', 'new_networks', 'newNetworks']),
      mergedSamples: pick(['merged_samples', 'merged', 'mergedSamples']),
      async: jobId != null && jobId.isNotEmpty,
      jobId: jobId,
    );
  }
}
