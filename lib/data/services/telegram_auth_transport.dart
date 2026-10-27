import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/data/services/network_retry.dart';

class TelegramAuthCancelled implements Exception {}

class TelegramAuthChallenge {
  const TelegramAuthChallenge({
    required this.host,
    required this.nonce,
    required this.botUsername,
    this.botUrl,
    this.tgUrl,
  });
  final String host, nonce, botUsername;
  final String? botUrl, tgUrl;
}

/// Select a reachable route with side-effect-free GETs before the only POST.
/// /request also configures the bot webhook; /check consumes a confirmed nonce.
/// Neither POST may be automatically replayed after an uncertain response.
class TelegramAuthTransport {
  TelegramAuthTransport({
    http.Client? client,
    List<String>? hosts,
    this.probeTimeout = const Duration(seconds: 3),
    this.requestTimeout = const Duration(seconds: 8),
    this.checkTimeout = const Duration(seconds: 4),
  }) : _client = client ?? http.Client(),
       hosts = List.unmodifiable(hosts ?? BackendConfig.notifierHosts);
  final http.Client _client;
  final List<String> hosts;
  final Duration probeTimeout, requestTimeout, checkTimeout;
  Map<String, String> get _headers => {
    'content-type': 'application/json',
    if (BackendConfig.notifierSecret.isNotEmpty)
      'x-install-secret': BackendConfig.notifierSecret,
  };

  void _wanted(bool Function() stillWanted) {
    if (!stillWanted()) throw TelegramAuthCancelled();
  }

  Future<TelegramAuthChallenge> createChallenge({
    required bool Function() stillWanted,
  }) async {
    String? selected;
    final start = NotifierRoute.preferredIndex(hosts);
    for (var i = 0; i < hosts.length; i++) {
      _wanted(stillWanted);
      final host = hosts[(start + i) % hosts.length];
      try {
        // This public, CORS-enabled status only reads payment configuration;
        // it creates no payment, auth nonce, webhook or notification.
        final request = http.Request('GET', Uri.parse('$host/api/pay/status'))
          ..followRedirects = false;
        final response = await (() async => http.Response.fromStream(
          await _client.send(request),
        ))().timeout(probeTimeout);
        _wanted(stillWanted);
        Object? health;
        try {
          health = jsonDecode(response.body);
        } catch (_) {
          /* Try the next read-only route. */
        }
        if (response.statusCode == 200 &&
            health is Map &&
            health['ok'] == true &&
            health['available'] is bool) {
          selected = host;
          break;
        }
      } catch (error) {
        if (error is TelegramAuthCancelled || !isRetryableNetworkError(error)) {
          rethrow;
        }
      }
    }
    _wanted(stillWanted);
    if (selected == null) {
      throw http.ClientException('Telegram route unavailable');
    }
    final response = await _post(
      selected,
      '/api/auth/telegram/request',
    ).timeout(requestTimeout);
    _wanted(stillWanted);
    if (response.statusCode != 200) {
      throw StateError('Telegram request rejected');
    }
    final data = jsonDecode(response.body);
    if (data is! Map ||
        data['ok'] != true ||
        data['nonce'] is! String ||
        !RegExp(
          r'^auth_[A-Za-z0-9_]{1,75}$',
        ).hasMatch(data['nonce'] as String) ||
        data['botUsername'] is! String ||
        (data['botUsername'] as String).isEmpty ||
        (data['botUrl'] != null && data['botUrl'] is! String) ||
        (data['tgUrl'] != null && data['tgUrl'] is! String)) {
      throw const FormatException('Invalid Telegram challenge');
    }
    NotifierRoute.remember(selected);
    return TelegramAuthChallenge(
      host: selected,
      nonce: data['nonce'] as String,
      botUsername: data['botUsername'] as String,
      botUrl: data['botUrl'] as String?,
      tgUrl: data['tgUrl'] as String?,
    );
  }

  Future<http.Response> _post(String host, String path, {String? body}) async {
    final request = http.Request('POST', Uri.parse('$host$path'))
      ..followRedirects = false
      ..headers.addAll(_headers);
    if (body != null) request.body = body;
    return http.Response.fromStream(await _client.send(request));
  }

  /// Exactly one check. A lost response may already have consumed this nonce.
  Future<http.Response> check(TelegramAuthChallenge challenge) {
    if (!hosts.contains(challenge.host)) {
      throw StateError('Unknown Telegram route');
    }
    return _post(
      challenge.host,
      '/api/auth/telegram/check',
      body: jsonEncode({'nonce': challenge.nonce}),
    ).timeout(checkTimeout);
  }

  void close() => _client.close();
}
