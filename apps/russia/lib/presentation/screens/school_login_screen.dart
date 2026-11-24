import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/school_login_route.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/auth_modal_sheet.dart';
import 'package:url_launcher/url_launcher.dart';

class SchoolLoginScreen extends StatefulWidget {
  const SchoolLoginScreen({super.key, required this.route, this.authReturn});
  final SchoolLoginRoute route;
  final Map<String, String>? authReturn;

  @override
  State<SchoolLoginScreen> createState() => _SchoolLoginScreenState();
}

class _SchoolLoginScreenState extends State<SchoolLoginScreen> {
  final auth = AuthService.instance;
  bool busy = false;
  String? error;
  bool processedReturn = false;

  Future<bool> _finishProvider() async {
    processedReturn = true;
    return auth.completeWebSignIn(widget.authReturn!);
  }

  Future<void> _continue() async {
    final owner = auth.currentUser?.id;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await http
          .post(
            Uri.parse(
              '${BackendConfig.notifierUrl}/api/auth/schools/authorize',
            ),
            headers: auth.serverHeaders,
            body: jsonEncode({'challenge': widget.route.challenge}),
          )
          .timeout(const Duration(seconds: 12));
      if (!mounted || owner != auth.currentUser?.id) return;
      if (response.statusCode == 401) {
        await auth.signOut();
        return;
      }
      if (response.statusCode != 200) throw const FormatException();
      final code = jsonDecode(response.body)['code'];
      if (code is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(code)) {
        throw const FormatException();
      }
      if (!await launchUrl(
        widget.route.callback(code),
        webOnlyWindowName: '_self',
      )) {
        throw const FormatException();
      }
    } catch (_) {
      if (mounted) setState(() => error = appL10n.authErrorNetwork);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: ListenableBuilder(
              listenable: auth,
              builder: (context, _) {
                final user = auth.currentUser;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      appL10n.schoolPortalLogin,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 24),
                    if (user == null || !auth.hasServerSession)
                      AuthModalSheet(
                        embedded: true,
                        initialAction:
                            widget.authReturn == null || processedReturn
                            ? null
                            : _finishProvider,
                      )
                    else ...[
                      Text(
                        user.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (user.email.isNotEmpty) Text(user.email),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: busy ? null : _continue,
                        child: Text(appL10n.continueButton),
                      ),
                      TextButton(
                        onPressed: busy ? null : auth.signOut,
                        child: Text(appL10n.checkoutChangeAccount),
                      ),
                    ],
                    if (error != null) Text(error!, semanticsLabel: error),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}
