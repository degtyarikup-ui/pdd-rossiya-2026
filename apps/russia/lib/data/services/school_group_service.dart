import 'dart:convert';
import 'auth_service.dart';
import 'notifier_api.dart';

class SchoolGroup {
  SchoolGroup(Map<String, dynamic> data)
    : id = data['id'] as String,
      name = data['name'] as String,
      school = data['school'] as String,
      instructor = data['instructor'] as String;
  final String id, name, school, instructor;
}

class SchoolMembership {
  SchoolMembership(Map<String, dynamic> data)
    : current = data['current'] == null ? null : SchoolGroup(data['current']),
      invited = data['group'] == null ? null : SchoolGroup(data['group']),
      version = data['version'] as String,
      consentVersion = data['consentVersion'] as String?;
  final SchoolGroup? current, invited;
  final String version;
  final String? consentVersion;
}

class SchoolGroupError implements Exception {
  const SchoolGroupError(this.status);
  final int status;
}

Future<SchoolMembership> schoolGroupRequest(
  String action,
  Map<String, String> data,
) async {
  final response = await NotifierApi.post(
    '/api/auth/schools/group/$action',
    headers: AuthService.instance.serverHeaders,
    body: jsonEncode(data),
    idempotent: action == 'mine' || action == 'preview',
  );
  if (response.statusCode != 200) throw SchoolGroupError(response.statusCode);
  return SchoolMembership(jsonDecode(response.body) as Map<String, dynamic>);
}
