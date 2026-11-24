import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/school_login_route.dart';
import 'package:pdd_app/data/services/notifier_api.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/auth_modal_sheet.dart';
import 'package:pdd_app/presentation/widgets/user_avatar.dart';
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
    if (busy) return;
    final owner = auth.currentUser?.id;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await NotifierApi.post(
        '/api/auth/schools/authorize',
        idempotent: false,
        headers: auth.serverHeaders,
        body: jsonEncode({'challenge': widget.route.challenge}),
      );
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

  Future<void> _switchAccount() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await auth.signOut();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _buildAccountActions(BuildContext context, Widget? _) {
    final colors = AppColors.of(context);
    final user = auth.currentUser;
    if (user == null || !auth.hasServerSession) {
      return AuthModalSheet(
        embedded: true,
        embeddedErrorColor: Theme.of(context).colorScheme.error,
        initialAction: widget.authReturn == null || processedReturn
            ? null
            : _finishProvider,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AccountIdentity(user),
        if (error != null) ...[
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
        const SizedBox(height: 28),
        FilledButton(
          onPressed: busy ? null : _continue,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            visualDensity: VisualDensity.standard,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  appL10n.schoolPortalEnter,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (busy)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.arrow_forward_rounded, size: 20),
            ],
          ),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: busy ? null : _switchAccount,
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: colors.isDark
                ? const Color(0xFFBCC0CC)
                : const Color(0xFF575D70),
            visualDensity: VisualDensity.standard,
            textStyle: const TextStyle(
              fontFamily: 'Onest',
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          child: Text(appL10n.schoolPortalSwitch, textAlign: TextAlign.center),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => _SchoolLoginPanel(
    child: ListenableBuilder(listenable: auth, builder: _buildAccountActions),
  );
}

class _SchoolLoginPanel extends StatelessWidget {
  const _SchoolLoginPanel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset(
                'assets/images/app_icon.png',
                width: 34,
                height: 34,
                excludeFromSemantics: true,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                appL10n.schoolPortalBrand,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Semantics(
          header: true,
          child: Text(
            appL10n.schoolPortalLogin,
            style: TextStyle(
              fontSize: 32,
              height: 1.13,
              letterSpacing: -0.9,
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
        ),
        const SizedBox(height: 24),
        child,
      ],
    );
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 500;
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 448),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: compact
                          ? colors.background
                          : colors.cardBackground,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 0 : 36),
                      child: content,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AccountIdentity extends StatelessWidget {
  const _AccountIdentity(this.user);
  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final provider = switch (user.provider) {
      AuthProviderType.google => appL10n.profileProviderGoogle,
      AuthProviderType.yandex => appL10n.profileProviderYandex,
      AuthProviderType.telegram => 'Telegram',
      AuthProviderType.apple => 'Apple ID',
    };
    final name = user.name.trim();
    final email = user.email.trim();
    final title = name.isEmpty ? provider : name;
    final detail = email.isNotEmpty ? email : provider;
    return Row(
      children: [
        ExcludeSemantics(
          child: UserAvatar(
            url: user.avatarUrl,
            useDefault: user.useDefaultAvatar,
            size: 48,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: colors.primaryText,
                  fontSize: 18,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (detail != title) ...[
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: TextStyle(
                    color: colors.isDark
                        ? const Color(0xFFA8ACBA)
                        : const Color(0xFF575D70),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
