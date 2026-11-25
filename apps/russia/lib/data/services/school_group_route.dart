/// Only an invitation or the student's own group may be restored after OAuth.
class SchoolGroupRoute {
  static final _token = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:[A-Za-z0-9_-]{43}$',
  );
  static final _code = RegExp(r'^[23456789A-HJ-NP-Z]{10}$');

  static String? parse(Object? value) {
    if (value is! String) return null;
    if (value == 'my' || _token.hasMatch(value)) return value;
    final code = value.replaceAll(RegExp(r'[- ]'), '').toUpperCase();
    return _code.hasMatch(code) ? code : null;
  }

  static String? fromLink(Uri uri) {
    if ((uri.hasScheme || uri.hasAuthority) &&
        (uri.scheme != 'https' ||
            !const {
              'schools.pdd-drive.app',
              'join.pdd-drive.app',
            }.contains(uri.host))) {
      return null;
    }
    if (uri.path == '/student/') return 'my';
    final parts = uri.pathSegments.where((v) => v.isNotEmpty).toList();
    return parts.length == 2 && parts.first == 'join'
        ? parse(parts.last)
        : null;
  }
}
