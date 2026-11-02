/// Polite HTTP for the collector: one request at a time, a pause between
/// requests, a timeout and two retries (ADR 0048).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Identifies the collector to the portals.
const String collectorUserAgent =
    'Mozilla/5.0 (compatible; ParselAppCollector/1.0; '
    '+https://github.com/oguzhankonca/parsel-bank-data)';

class CollectorHttpException implements Exception {
  CollectorHttpException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CollectorHttp {
  CollectorHttp({
    this.pause = const Duration(milliseconds: 1200),
    this.timeout = const Duration(seconds: 30),
  });

  final Duration pause;
  final Duration timeout;
  final HttpClient _client = HttpClient()..userAgent = collectorUserAgent;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// Number of requests sent, for the run log.
  int requests = 0;

  Future<String> getText(String url) => _send('GET', url, null);

  Future<Object?> postJson(String url, Object body) async {
    final String text = await _send('POST', url, jsonEncode(body));
    return jsonDecode(text);
  }

  Future<String> _send(String method, String url, String? body) async {
    Object? lastError;
    for (int attempt = 0; attempt < 3; attempt++) {
      await _wait();
      try {
        return await _once(method, url, body).timeout(timeout);
      } on Object catch (error) {
        lastError = error;
        await Future<void>.delayed(Duration(seconds: 3 * (attempt + 1)));
      }
    }
    throw CollectorHttpException('$method $url: $lastError');
  }

  Future<void> _wait() async {
    final Duration since = DateTime.now().difference(_last);
    if (since < pause) {
      await Future<void>.delayed(pause - since);
    }
    _last = DateTime.now();
    requests++;
  }

  Future<String> _once(String method, String url, String? body) async {
    final HttpClientRequest request = await _client.openUrl(
      method,
      Uri.parse(url),
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json, */*');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(body);
    }
    final HttpClientResponse response = await request.close();
    final String text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw CollectorHttpException('HTTP ${response.statusCode}');
    }
    return text;
  }

  void close() => _client.close(force: true);
}
