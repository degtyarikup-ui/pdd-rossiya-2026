class SchoolLoginRoute {
  const SchoolLoginRoute(this.challenge, this.state);
  final String challenge;
  final String state;

  static SchoolLoginRoute? parse(Object? challenge, Object? state) {
    final token = RegExp(r'^[a-f0-9]{64}$');
    return challenge is String &&
            state is String &&
            token.hasMatch(challenge) &&
            token.hasMatch(state)
        ? SchoolLoginRoute(challenge, state)
        : null;
  }

  static SchoolLoginRoute? resolve(Uri uri, Map<String, String>? returned) =>
      parse(
        uri.queryParameters['school_login'],
        uri.queryParameters['school_state'],
      ) ??
      parse(returned?['school_login'], returned?['school_state']);

  Uri callback(String code) => Uri.https(
    'schools.pdd-drive.app',
    '/accounts/pdd/callback/',
    {'code': code, 'state': state},
  );
}
