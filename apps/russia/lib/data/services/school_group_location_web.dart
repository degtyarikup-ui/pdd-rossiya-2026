import 'package:web/web.dart' as web;

void setSchoolGroupLocation(String invite) {
  final current = Uri.base;
  web.window.history.replaceState(
    null,
    '',
    current
        .replace(
          queryParameters: {...current.queryParameters, 'school_group': invite},
        )
        .toString(),
  );
}
