// Isolated native preview, without sign-in or notification onboarding:
// flutter run -t tools/game_preview.dart --dart-define=COUNTRY=ru
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/game/game_screen.dart';
import 'package:pdd_app/presentation/screens/game/controllers/game_controller.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  // Test-only VM service hook; this entrypoint is never used by release builds.
  developer.registerExtension('ext.pdd.gamePreview', (
    method,
    parameters,
  ) async {
    WebViewController? webview;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is WebViewWidget) {
        webview = WebViewController.fromPlatform(
          widget.platform.params.controller,
        );
      }
      element.visitChildren(visit);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root);
    final action = parameters['action'];
    final controller = container.read(gameControllerProvider.notifier);
    if (action == 'gas') {
      await webview?.runJavaScript('window.game.setGas(true)');
    } else if (action == 'release') {
      await webview?.runJavaScript('window.game.setGas(false)');
    } else if (action == 'left' || action == 'right' || action == 'straight') {
      await webview?.runJavaScript(
        'window.game.setSteering(${action == 'left'
            ? 1
            : action == 'right'
            ? -1
            : 0})',
      );
    } else if (action == 'answer') {
      controller.submitAnswer(int.parse(parameters['index']!));
    } else if (action == 'continue') {
      controller.continueAfterExplanation();
    }
    final state = container.read(gameControllerProvider);
    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'phase': state.phase.name,
        'distance': state.distanceM,
        'score': state.score,
        'oncoming': state.oncoming,
        'violations': state.violationCount,
        'situation': state.currentSituation?.toJson(),
        'paused': state.paused,
      }),
    );
  });
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const GameScreen(),
      ),
    ),
  );
}
