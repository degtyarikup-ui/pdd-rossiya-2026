import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:webview_flutter/webview_flutter.dart';

class YandexAuthSheet extends StatefulWidget {
  const YandexAuthSheet({super.key});

  static Future<UserProfile?> show(BuildContext context) {
    HapticFeedbackHelper.tap();
    return showModalBottomSheet<UserProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const YandexAuthSheet(),
    );
  }

  @override
  State<YandexAuthSheet> createState() => _YandexAuthSheetState();
}

class _YandexAuthSheetState extends State<YandexAuthSheet> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isProcessingToken = false;

  static const String _redirectScheme = 'ru.pdd.pddapp://oauth';

  @override
  void initState() {
    super.initState();
    final authUrl = Uri.parse(
      'https://oauth.yandex.ru/authorize?response_type=token&client_id=${AuthService.yandexClientId}&redirect_uri=$_redirectScheme',
    );

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            _checkUrlForToken(url);
          },
          onPageFinished: (url) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
            _checkUrlForToken(url);
          },
          onNavigationRequest: (request) {
            if (request.url.startsWith(_redirectScheme) ||
                request.url.contains('access_token=')) {
              _checkUrlForToken(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(authUrl);
  }

  Future<void> _checkUrlForToken(String url) async {
    if (_isProcessingToken) return;

    if (url.startsWith(_redirectScheme) || url.contains('access_token=')) {
      _isProcessingToken = true;
      if (mounted) setState(() => _isLoading = true);

      try {
        final uri = Uri.parse(url.replaceFirst('#', '?'));
        final token = uri.queryParameters['access_token'];

        if (token != null && token.isNotEmpty) {
          final profile = await _fetchYandexProfile(token);
          if (mounted && profile != null) {
            Navigator.of(context).pop(profile);
            return;
          }
        }
      } catch (e) {
        debugPrint('YandexAuthSheet: parse token error: $e');
      }

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.of(context).pop();
      }
    }
  }

  Future<UserProfile?> _fetchYandexProfile(String token) async {
    try {
      final response = await http.get(
        Uri.parse('https://login.yandex.ru/info?format=json'),
        headers: {'Authorization': 'OAuth $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final id = data['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
        
        final realName = data['real_name'] as String?;
        final displayName = data['display_name'] as String?;
        final firstName = data['first_name'] as String?;
        final lastName = data['last_name'] as String?;
        
        String name = 'Пользователь Яндекс';
        if (realName != null && realName.isNotEmpty) {
          name = realName;
        } else if (displayName != null && displayName.isNotEmpty) {
          name = displayName;
        } else if (firstName != null && firstName.isNotEmpty) {
          name = [firstName, lastName].where((s) => s != null && s.isNotEmpty).join(' ');
        }

        final email = data['default_email'] as String? ?? 
            (data['emails'] is List && (data['emails'] as List).isNotEmpty
                ? (data['emails'] as List).first.toString()
                : 'user@yandex.ru');

        final defaultAvatarId = data['default_avatar_id'] as String?;
        final isAvatarEmpty = data['is_avatar_empty'] == true;
        final avatarUrl = (!isAvatarEmpty && defaultAvatarId != null && defaultAvatarId.isNotEmpty)
            ? 'https://avatars.yandex.net/get-yapic/$defaultAvatarId/islands-200'
            : null;

        return UserProfile(
          id: 'yandex_$id',
          name: name,
          email: email,
          avatarUrl: avatarUrl,
          provider: AuthProviderType.yandex,
          createdAt: DateTime.now(),
        );
      }
    } catch (e) {
      debugPrint('YandexAuthSheet: fetch profile error: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Container(
      height: screenHeight * 0.88,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.screenPadding,
                8,
                8,
                8,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFC3F1D),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text(
                            'Я',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Вход с Яндекс ID',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colors.primaryText,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: colors.secondaryText),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            if (_isLoading)
              const LinearProgressIndicator(
                minHeight: 2,
                color: Color(0xFFFC3F1D),
                backgroundColor: Colors.transparent,
              ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: WebViewWidget(controller: _controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
