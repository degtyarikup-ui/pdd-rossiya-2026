import 'package:flutter/widgets.dart';

class GoogleWebSignInButton extends StatelessWidget {
  const GoogleWebSignInButton({
    super.key,
    required this.onSignIn,
    required this.onError,
    required this.enabled,
  });
  final Future<void> Function(Future<String> Function()) onSignIn;
  final ValueChanged<Object> onError;
  final bool enabled;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
