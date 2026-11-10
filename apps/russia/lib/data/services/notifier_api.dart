import 'package:http/http.dart' as http;
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/data/services/dev_mock_endpoint.dart';
import 'package:pdd_app/data/services/network_errors_stub.dart'
    if (dart.library.io) 'package:pdd_app/data/services/network_errors_io.dart';
import 'package:pdd_app/data/services/network_retry.dart';

/// Retry only operations whose server contract is idempotent. Payment creation
/// and paid AI requests use one attempt at the route that last worked for auth;
/// the other route is tried only when the first was provably never reached.
class NotifierApi {
  /// One delivery of an operation that must not run twice. When the preferred
  /// address cannot even be connected to (blocked name, refused route, broken
  /// TLS handshake) the request never left the device, so the other address
  /// may take it. Any other failure has an unknown outcome and is returned.
  static Future<http.Response> _postOnce(
    String path, {
    Map<String, String>? headers,
    String? body,
  }) async {
    final hosts = BackendConfig.notifierHosts;
    final start = NotifierRoute.preferredIndex(hosts);
    for (var i = 0; ; i++) {
      final host = hosts[(start + i) % hosts.length];
      try {
        final response = await http
            .post(Uri.parse('$host$path'), headers: headers, body: body)
            .timeout(const Duration(seconds: 30));
        if (i > 0) NotifierRoute.remember(host);
        return response;
      } catch (error) {
        if (i + 1 >= hosts.length || !requestNeverSent(error)) rethrow;
      }
    }
  }

  static Uri uri(String path, [Map<String, String>? query]) => Uri.parse(
    '${BackendConfig.notifierHosts[NotifierRoute.preferredIndex(BackendConfig.notifierHosts)]}$path',
  ).replace(queryParameters: query);

  static Future<http.Response> get(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? query,
  }) {
    if (DevMockEndpoint.shouldHandle(headers)) {
      return DevMockEndpoint.handleGet(path, headers: headers, query: query);
    }
    return sendWithRetry(
      (host) => http.get(
        Uri.parse('$host$path').replace(queryParameters: query),
        headers: headers,
      ),
      hosts: BackendConfig.notifierHosts,
      attempts: const [Duration(seconds: 8), Duration(seconds: 8)],
      pause: Duration.zero,
    );
  }

  /// Store receipt checks wait for Apple/Google inside the account's queue;
  /// the server ends them with 503 after 25 seconds. A shorter wait abandoned
  /// work the server still finished and queued the retry behind it.
  static const storeVerificationAttempts = [
    Duration(seconds: 40),
    Duration(seconds: 20),
  ];

  static Future<http.Response> post(
    String path, {
    required bool idempotent,
    Map<String, String>? headers,
    String? body,
    List<Duration> attempts = const [
      Duration(seconds: 15),
      Duration(seconds: 15),
    ],
  }) {
    if (DevMockEndpoint.shouldHandle(headers)) {
      return DevMockEndpoint.handlePost(path, headers: headers, body: body);
    }
    if (!idempotent) return _postOnce(path, headers: headers, body: body);
    return sendWithRetry(
      (host) =>
          http.post(Uri.parse('$host$path'), headers: headers, body: body),
      hosts: BackendConfig.notifierHosts,
      attempts: attempts,
      pause: Duration.zero,
    );
  }
}
