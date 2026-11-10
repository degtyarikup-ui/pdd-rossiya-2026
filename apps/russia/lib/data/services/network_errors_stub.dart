bool isPlatformNetworkError(Object error) => false;

String? platformNetworkCode(Object error) => null;

/// A browser does not say whether a failed request left the device.
bool requestNeverSent(Object error) => false;
