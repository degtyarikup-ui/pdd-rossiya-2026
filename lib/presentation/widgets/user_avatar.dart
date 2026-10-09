import 'package:flutter/material.dart';

/// One avatar presentation in profile and rankings, including network failures.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.url,
    this.useDefault = false,
    this.size = 42,
  });
  final String? url;
  final bool useDefault;
  final double size;
  @override
  Widget build(BuildContext context) {
    Widget fallback() => Image.asset(
      'assets/images/default_avatar.webp',
      fit: BoxFit.cover,
      cacheWidth: 192,
    );
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: useDefault || url?.isNotEmpty != true
            ? fallback()
            : Image.network(
                url!,
                fit: BoxFit.cover,
                cacheWidth: 192,
                errorBuilder: (_, _, _) => fallback(),
              ),
      ),
    );
  }
}
