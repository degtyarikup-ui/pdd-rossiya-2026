import 'dart:convert';

enum AuthProviderType { google, apple, yandex }

class UserProfile {
  final String id;
  final String name;
  final String email;
  final String? avatarUrl;
  final bool useDefaultAvatar;
  final AuthProviderType provider;
  final DateTime createdAt;

  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    this.useDefaultAvatar = false,
    required this.provider,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'avatarUrl': avatarUrl,
      'useDefaultAvatar': useDefaultAvatar,
      'provider': provider.name,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      email: map['email'] as String,
      avatarUrl: map['avatarUrl'] as String?,
      useDefaultAvatar: map['useDefaultAvatar'] == true,
      provider: AuthProviderType.values.firstWhere(
        (p) => p.name == map['provider'],
        orElse: () => AuthProviderType.google,
      ),
      createdAt:
          DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  UserProfile withAvatarChoice(bool useDefault) => UserProfile(
    id: id,
    name: name,
    email: email,
    avatarUrl: avatarUrl,
    useDefaultAvatar: useDefault,
    provider: provider,
    createdAt: createdAt,
  );

  String toJson() => jsonEncode(toMap());

  factory UserProfile.fromJson(String source) =>
      UserProfile.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
