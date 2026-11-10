import 'dart:io';

// Retrying a transport failure uses the normal TLS verifier on every host.
// Never install badCertificateCallback or treat unrelated local I/O as network.
bool isPlatformNetworkError(Object error) =>
    error is SocketException ||
    error is HandshakeException ||
    error is HttpException;

/// The connection was never established, so the request cannot have reached
/// the server: the name did not resolve, the route or port refused, or the TLS
/// handshake did not complete. A timeout or a reset connection is not in this
/// list — the server may already have acted on such a request.
bool requestNeverSent(Object error) {
  if (error is HandshakeException) return true;
  if (error is! SocketException) return false;
  if (error.message.startsWith('Failed host lookup')) return true;
  // ECONNREFUSED, ENETUNREACH, EHOSTUNREACH on Linux/Android and on iOS/macOS.
  return const {111, 101, 113, 61, 51, 65}.contains(error.osError?.errorCode);
}

/// Report code for a transport failure. A failed TLS handshake (`network:tls`)
/// is typical of networks that interrupt connections to the server's host.
String? platformNetworkCode(Object error) => switch (error) {
  HandshakeException() => 'network:tls',
  SocketException() => 'network:socket',
  HttpException() => 'network:http',
  _ => null,
};
