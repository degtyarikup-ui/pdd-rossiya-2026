import 'dart:io';

// Retrying a transport failure uses the normal TLS verifier on every host.
// Never install badCertificateCallback or treat unrelated local I/O as network.
bool isPlatformNetworkError(Object error) =>
    error is SocketException ||
    error is HandshakeException ||
    error is HttpException;

/// Report code for a transport failure. A failed TLS handshake (`network:tls`)
/// is typical of networks that interrupt connections to the server's host.
String? platformNetworkCode(Object error) => switch (error) {
  HandshakeException() => 'network:tls',
  SocketException() => 'network:socket',
  HttpException() => 'network:http',
  _ => null,
};
