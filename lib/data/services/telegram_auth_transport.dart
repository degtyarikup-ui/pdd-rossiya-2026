import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/data/services/network_retry.dart';

class TelegramAuthHttpException implements Exception {
  const TelegramAuthHttpException(this.statusCode);
  final int statusCode;
  String get code => 'http_$statusCode';
}

class TelegramAuthCancelled implements Exception {}

class TelegramAuthChallenge {
  const TelegramAuthChallenge({
    required this.host,
    required this.nonce,
    required this.botUsername,
    this.verifier,
    this.botUrl,
    this.tgUrl,
  });
  final String host, nonce, botUsername;
  final String? botUrl, tgUrl, verifier;
}

/// Select a reachable route with side-effect-free GETs before the only POST.
/// Challenge creation is never replayed. Only v2 checks have a durable result
/// bound to a private verifier and can safely recover a lost response.
class TelegramAuthTransport {
  TelegramAuthTransport({
    http.Client? client,
    List<String>? hosts,
    this.probeTimeout = const Duration(seconds: 3),
    this.requestTimeout = const Duration(seconds: 8),
    this.checkTimeout = const Duration(seconds: 8),
    this.retryDelay = const Duration(seconds: 1),
  }) : _client = client ?? http.Client(),
       hosts = List.unmodifiable(hosts ?? BackendConfig.notifierHosts);
  final http.Client _client;
  final List<String> hosts;
  final Duration probeTimeout, requestTimeout, checkTimeout, retryDelay;
  bool _closed = false;
  Map<String, String> get _headers => {
    'content-type': 'application/json',
    if (BackendConfig.notifierSecret.isNotEmpty)
      'x-install-secret': BackendConfig.notifierSecret,
  };

  void _wanted(bool Function() stillWanted) {
    if (_closed || !stillWanted()) throw TelegramAuthCancelled();
  }

  Future<TelegramAuthChallenge> createChallenge({
    required bool Function() stillWanted,
  }) async {
    _wanted(stillWanted);
    final stats = RetryStats();
    try {
      await sendWithRetry(
        (host) async {
          // This public, CORS-enabled status only reads payment configuration;
          // it creates no payment, auth nonce, webhook or notification.
          final request = http.Request('GET', Uri.parse('$host/api/pay/status'))
            ..followRedirects = false;
          final response = await http.Response.fromStream(
            await _client.send(request),
          );
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
            return response;
          }
          throw http.ClientException('Invalid Telegram route response');
        },
        hosts: hosts,
        attempts: List.filled(hosts.length, probeTimeout),
        pause: Duration.zero,
        stillWanted: () => !_closed && stillWanted(),
        stats: stats,
        // Keep listening to an already sent GET while checking the fallback.
        // The overall route-selection budget is still one timeout per host.
        acceptLateSuccess: true,
      );
    } catch (error) {
      _wanted(stillWanted);
      if (!isRetryableNetworkError(error)) rethrow;
      throw http.ClientException('Telegram route unavailable');
    }
    _wanted(stillWanted);
    final selected = stats.host!;
    final response = await _post(
      selected,
      '/api/auth/telegram/request',
      body: jsonEncode({'protocolVersion': 2}),
    ).timeout(requestTimeout);
    _wanted(stillWanted);
    if (response.statusCode != 200) {
      throw TelegramAuthHttpException(response.statusCode);
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
    final verifier = data['protocolVersion'] == 2 ? data['verifier'] : null;
    if (data['protocolVersion'] == 2 &&
        (verifier is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(verifier))) {
      throw const FormatException('Invalid Telegram verifier');
    }
    NotifierRoute.remember(selected);
    return TelegramAuthChallenge(
      host: selected,
      verifier: verifier as String?,
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

  Future<http.Response> check(
    TelegramAuthChallenge challenge, {
    bool Function()? stillWanted,
  }) async {
    if (!hosts.contains(challenge.host)) {
      throw StateError('Unknown Telegram route');
    }
    final wanted = stillWanted ?? () => true;
    final attempts = challenge.verifier == null ? 1 : 3;
    for (var attempt = 1; ; attempt++) {
      _wanted(wanted);
      var delay = retryDelay * attempt;
      try {
        final response = await _post(
          challenge.host,
          '/api/auth/telegram/check',
          body: jsonEncode({
            'nonce': challenge.nonce,
            if (challenge.verifier != null) 'verifier': challenge.verifier,
          }),
        ).timeout(checkTimeout);
        _wanted(wanted);
        if (response.statusCode == 200) return response;
        final retryable = [
          429,
          500,
          502,
          503,
          504,
        ].contains(response.statusCode);
        if (!retryable || attempt >= attempts) {
          throw TelegramAuthHttpException(response.statusCode);
        }
        final retryAfter = response.headers['retry-after'];
        final seconds = int.tryParse(retryAfter ?? '');
        if (retryAfter != null && seconds == null) {
          throw TelegramAuthHttpException(response.statusCode);
        }
        if (seconds != null && seconds > 0) {
          // Do not ignore a server cooldown that exceeds this interaction.
          if (seconds > 10) {
            throw TelegramAuthHttpException(response.statusCode);
          }
          delay = Duration(seconds: seconds);
        }
      } catch (error) {
        if (attempt >= attempts || !isRetryableNetworkError(error)) rethrow;
      }
      await Future<void>.delayed(delay);
    }
  }

  void close() {
    _closed = true;
    _client.close();
  }
}
