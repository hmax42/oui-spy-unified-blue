import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

class WdgwarsApi {
  WdgwarsApi({required String apiKey})
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://wdgwars.pl',
          headers: {
            'X-API-Key': apiKey,
            HttpHeaders.userAgentHeader: 'oui-spy-companion/1.0',
          },
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

  /// Upload a CSV. Buffered body + explicit Content-Length, mirroring wdgwars'
  /// own client (LOCOSP/pineapple_pager_wdgwars uploader/wdgwars.py).
  Future<WdgwarsUploadResult> uploadCsv(
    File csvFile, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final csv = await csvFile.readAsBytes();
    if (csv.isEmpty) throw WdgwarsApiException('CSV is empty — nothing to upload');

    const retryDelays = [Duration(seconds: 2), Duration(seconds: 8)];
    Response<dynamic>? resp;
    Object? lastTransportError;

    for (var attempt = 0; attempt <= retryDelays.length; attempt++) {
      try {
        resp = await _postCsv(csvFile.uri.pathSegments.last, csv, onProgress);
        break;
      } on DioException catch (e) {
        if (!_isTransient(e)) throw WdgwarsApiException(_dioMessage(e));
        lastTransportError = e.error ?? e;
        if (attempt == retryDelays.length) break;
        _resetConnection();
        await Future<void>.delayed(retryDelays[attempt]);
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
      throw WdgwarsApiException('File too large — split the session');
    }
    if (code == 429) {
      final retry = resp.headers.value('retry-after');
      final wait = retry != null ? ' — retry in ${retry}s' : ' — try again shortly';
      throw WdgwarsApiException('Rate limited (30/min)$wait');
    }
    if (code == 202 || (code >= 200 && code < 300 && data['ok'] != false)) {
      return WdgwarsUploadResult.fromJson(data);
    }
    throw WdgwarsApiException(
        (data['error'] as String?) ?? 'Upload failed (HTTP $code)');
  }

  Future<Response<dynamic>> _postCsv(
    String filename,
    Uint8List csv,
    void Function(int sent, int total)? onProgress,
  ) {
    final boundary =
        '----ouispy${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    final head = utf8.encode('--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="$filename"\r\n'
        'Content-Type: text/csv\r\n\r\n');
    final tail = utf8.encode('\r\n--$boundary--\r\n');

    final body = Uint8List(head.length + csv.length + tail.length);
    body.setRange(0, head.length, head);
    body.setRange(head.length, head.length + csv.length, csv);
    body.setRange(head.length + csv.length, body.length, tail);

    return _dio.post(
      '/api/upload-csv',
      data: Stream.value(body),
      onSendProgress: onProgress,
      options: Options(
        headers: {
          Headers.contentTypeHeader:
              'multipart/form-data; boundary=$boundary',
          Headers.contentLengthHeader: body.length,
        },
        sendTimeout: _sendTimeoutFor(body.length),
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

  /// Reference client treats 400/401/403/413/415 as final, everything else retryable.
  static bool _isTransient(DioException e) {
    final code = e.response?.statusCode;
    if (code != null) {
      return !(code == 400 || code == 401 || code == 403 ||
          code == 413 || code == 415);
    }
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

  static String _transportMessage(Object? err) =>
      'Upload aborted: ${err ?? 'connection closed by server'}';

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
