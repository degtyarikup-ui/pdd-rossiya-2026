import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleWebSignInButton extends StatelessWidget {
  const GoogleWebSignInButton({
    super.key,
    required this.onAccount,
    required this.onError,
    required this.enabled,
  });
  final ValueChanged<GoogleSignInAccount> onAccount;
  final ValueChanged<Object> onError;
  final bool enabled;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
