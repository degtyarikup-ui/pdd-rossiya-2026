import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/error_reporter.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:url_launcher/url_launcher.dart';

class TelegramAuthResult {
  final UserProfile user;
  final String token;
  final DateTime expiresAt;

  const TelegramAuthResult({
    required this.user,
    required this.token,
    required this.expiresAt,
  });
}

class TelegramAuthSheet extends StatefulWidget {
  const TelegramAuthSheet({super.key});

  static Future<TelegramAuthResult?> show(BuildContext context) {
    HapticFeedbackHelper.tap();
    return showModalBottomSheet<TelegramAuthResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TelegramAuthSheet(),
    );
  }

  @override
  State<TelegramAuthSheet> createState() => _TelegramAuthSheetState();
}

class _TelegramAuthSheetState extends State<TelegramAuthSheet>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  String? _error;
  String? _nonce;
  String? _botUrl;
  String? _tgUrl;
  String _botUsername = 'pdda_bot';
  Timer? _pollTimer;
  int _pollCount = 0;
  bool _checking = false;
  bool _done = false;
  static const int _maxPollAttempts = 60; // 60 * 1.5s = 90s

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startAuthFlow();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Вернулись из Telegram — проверяем сразу, не дожидаясь таймера.
    if (state == AppLifecycleState.resumed &&
        _pollTimer != null &&
        _error == null) {
      _checkStatus(_pollTimer!);
    }
  }

  Future<void> _startAuthFlow() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse('${BackendConfig.notifierUrl}/api/auth/telegram/request'),
            headers: {
              'content-type': 'application/json',
              if (BackendConfig.notifierSecret.isNotEmpty)
                'x-install-secret': BackendConfig.notifierSecret,
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw StateError('Server error: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['ok'] != true || data['nonce'] == null) {
        throw StateError('Invalid response format');
      }

      _nonce = data['nonce'] as String;
      _botUrl = data['botUrl'] as String?;
      _tgUrl = data['tgUrl'] as String?;
      _botUsername = (data['botUsername'] as String?) ?? 'pdda_bot';

      if (mounted) {
        setState(() => _isLoading = false);
        _startPolling();
        unawaited(_openTelegram());
      }
    } catch (e) {
      debugPrint('TelegramAuthSheet: start error: $e');
      ErrorReporter.report(
        ErrorCategory.auth,
        'telegram.request',
        error: e,
        provider: 'telegram',
      );
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = appL10n.authErrorServer;
        });
      }
    }
  }

  Future<void> _openTelegram() async {
    if (_tgUrl != null) {
      final uri = Uri.parse(_tgUrl!);
      try {
        if (await canLaunchUrl(uri)) {
          final launched = await launchUrl(
            uri,
            mode: LaunchMode.externalNonBrowserApplication,
          );
          if (launched) return;
        }
      } catch (_) {}
    }

    if (_botUrl != null) {
      final webUri = Uri.parse(_botUrl!);
      try {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('TelegramAuthSheet: open web error: $e');
      }
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollCount = 0;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      _checkStatus(timer);
    });
  }

  Future<void> _checkStatus(Timer timer) async {
    if (!mounted || _nonce == null || _done) {
      timer.cancel();
      return;
    }
    if (_checking) return;
    _checking = true;
    try {
      await _doCheck(timer);
    } finally {
      _checking = false;
    }
  }

  Future<void> _doCheck(Timer timer) async {

    _pollCount++;
    if (_pollCount > _maxPollAttempts) {
      timer.cancel();
      if (mounted) {
        setState(() => _error = appL10n.authErrorTimeout);
      }
      return;
    }

    try {
      final response = await http
          .post(
            Uri.parse('${BackendConfig.notifierUrl}/api/auth/telegram/check'),
            headers: {
              'content-type': 'application/json',
              if (BackendConfig.notifierSecret.isNotEmpty)
                'x-install-secret': BackendConfig.notifierSecret,
            },
            body: jsonEncode({'nonce': _nonce}),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['ok'] == true && data['status'] == 'confirmed') {
          timer.cancel();
          _done = true;
          final userMap = Map<String, dynamic>.from(data['user'] as Map);
          final user = UserProfile.fromMap(userMap);
          final token = data['token'] as String;
          final expiresAt = DateTime.parse(data['expiresAt'] as String);

          if (mounted) {
            Navigator.of(context).pop(
              TelegramAuthResult(
                user: user,
                token: token,
                expiresAt: expiresAt,
              ),
            );
          }
        } else if (data['status'] == 'invalid') {
          timer.cancel();
          if (mounted) setState(() => _error = appL10n.authErrorServer);
        } else if (data['status'] == 'expired') {
          timer.cancel();
          if (mounted) {
            setState(() => _error = appL10n.authErrorTimeout);
          }
        }
      } else {
        debugPrint('TelegramAuthSheet: check status ${response.statusCode}');
      }
    } catch (e) {
      // Единичные сетевые сбои опроса игнорируем
      debugPrint('TelegramAuthSheet: poll error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.screenPadding,
            12,
            AppDimensions.screenPadding,
            24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: colors.secondaryText,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF24A1DE),
                    shape: BoxShape.circle,
                  ),
                  child: SvgPicture.asset(
                    'assets/icons/auth/telegram.svg',
                    width: 40,
                    height: 40,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                appL10n.authTelegramWaitingTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                appL10n.authTelegramWaitingDesc(_botUsername),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: 24),
              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Color(0xFF24A1DE),
                  ),
                )
              else if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _startAuthFlow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.searchFieldFill,
                    foregroundColor: colors.primaryText,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(appL10n.authFailed),
                ),
              ] else ...[
                const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Color(0xFF24A1DE),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _openTelegram,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF24A1DE),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    appL10n.authTelegramOpenAgain,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
