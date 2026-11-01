import 'package:http/http.dart' as http;
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/data/services/network_retry.dart';

/// Retry only operations whose server contract is idempotent. Payment creation
/// and paid AI requests use one attempt at the route that last worked for auth.
class NotifierApi {
  static Uri uri(String path, [Map<String, String>? query]) => Uri.parse(
    '${BackendConfig.notifierHosts[NotifierRoute.preferredIndex(BackendConfig.notifierHosts)]}$path',
  ).replace(queryParameters: query);

  static Future<http.Response> get(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? query,
  }) => sendWithRetry(
    (host) => http.get(
      Uri.parse('$host$path').replace(queryParameters: query),
      headers: headers,
    ),
    hosts: BackendConfig.notifierHosts,
    attempts: const [Duration(seconds: 8), Duration(seconds: 8)],
    pause: Duration.zero,
  );

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
    if (!idempotent) {
      return http
          .post(uri(path), headers: headers, body: body)
          .timeout(const Duration(seconds: 30));
    }
    return sendWithRetry(
      (host) =>
          http.post(Uri.parse('$host$path'), headers: headers, body: body),
      hosts: BackendConfig.notifierHosts,
      attempts: attempts,
      pause: Duration.zero,
    );
  }
}
