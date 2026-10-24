import 'dart:io';

// Retrying a transport failure uses the normal TLS verifier on every host.
// Never install badCertificateCallback or treat unrelated local I/O as network.
bool isPlatformNetworkError(Object error) =>
    error is SocketException ||
    error is HandshakeException ||
    error is HttpException;
