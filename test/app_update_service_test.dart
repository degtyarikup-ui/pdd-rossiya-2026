import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/core/navigation/route_observer.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/presentation/screens/home/home_screen.dart';
import 'package:pdd_app/data/services/app_update_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/app_update_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pdd/app_updates');
  final binding =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final installed = PackageInfo(
    appName: 'PDD',
    packageName: 'ru.pdd.pdd_app',
    version: '2.1.8',
    buildNumber: '48',
    installerStore: 'com.apple',
  );
  final policy = <String, dynamic>{
    'enabled': true,
    'app': 'ru',
    'platform': 'ios',
    'packageId': installed.packageName,
    'version': '2.1.9',
    'build': 49,
    'storeUrl': 'https://apps.apple.com/ru/app/id6792369533',
    'notes': 'Исправлены заезды',
  };
  final listing = <String, dynamic>{
    'bundleId': installed.packageName,
    'version': '2.1.9',
    'minimumOsVersion': '14.0',
  };
  Map<String, dynamic>? play;
  String startResult = 'accepted';
  bool completeResult = true;
  final nativeCalls = <String>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    play = {
      'available': true,
      'build': 49,
      'flexible': true,
      'downloaded': false,
      'downloading': false,
    };
    startResult = 'accepted';
    completeResult = true;
    nativeCalls.clear();
    binding.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call.method);
      return switch (call.method) {
        'check' => play,
        'start' => startResult,
        'complete' => completeResult,
        _ => null,
      };
    });
  });
  tearDown(() => binding.setMockMethodCallHandler(channel, null));
  AppUpdateService service({
    TargetPlatform platform = TargetPlatform.iOS,
    Map<String, dynamic>? release,
    Map<String, dynamic>? store,
    int status = 200,
    PackageInfo? package,
    DateTime Function()? now,
    Future<bool> Function(Uri)? launch,
    String os = '26.0',
    String country = 'ru',
    bool enabled = true,
  }) => AppUpdateService.forTesting(
    platform: platform,
    package: () async => package ?? installed,
    now: now,
    launch: launch,
    iosSystemVersion: () async => os,
    country: country,
    enabled: enabled,
    client: MockClient(
      (request) async => http.Response(
        jsonEncode(
          request.url.host == 'itunes.apple.com'
              ? {
                  'results': [store ?? listing],
                }
              : {'release': release ?? policy},
        ),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    ),
  );

  test(
    'numeric versions handle 2.10, missing components and invalid versions',
    () {
      expect(compareStoreVersions('2.10.0', '2.9.9'), 1);
      expect(compareStoreVersions('2.1', '2.1.0'), 0);
      expect(compareStoreVersions('2.beta', '2.0'), isNull);
    },
  );
  test(
    'iOS requires published exact version, matching bundle and compatible OS',
    () async {
      expect((await service().check())?.version, '2.1.9');
      for (final bad in [
        {'enabled': false},
        {'build': 48},
        {'version': '2.1.8'},
        {'packageId': 'other.app'},
        {'app': 'by'},
        {'platform': 'android'},
        {'storeUrl': 'https://evil.test/id123'},
      ]) {
        expect(
          await service(release: {...policy, ...bad}).check(),
          isNull,
          reason: bad.toString(),
        );
      }
      expect(
        await service(store: {...listing, 'version': '2.1.8'}).check(),
        isNull,
      );
      expect(
        await service(store: {...listing, 'bundleId': 'other.app'}).check(),
        isNull,
      );
      expect(await service(os: '13.5').check(), isNull);
      expect(await service(status: 503).check(), isNull);
      expect(
        await service(
          package: PackageInfo(
            appName: 'PDD',
            packageName: installed.packageName,
            version: '2.1.8',
            buildNumber: '48',
            installerStore: 'com.apple.testflight',
          ),
        ).check(),
        isNull,
      );
    },
  );
  test(
    'Android eligibility comes from Play; remote notes cannot invent a release',
    () async {
      final androidPolicy = {...policy, 'platform': 'android'};
      final app = service(
        platform: TargetPlatform.android,
        release: androidPolicy,
      );
      final offer = await app.check();
      expect(offer?.flexible, true);
      expect(offer?.notes, policy['notes']);
      expect(offer?.storeUrl.queryParameters['id'], installed.packageName);
      play = null;
      expect(await service(platform: TargetPlatform.android).check(), isNull);
      play = {'available': false, 'build': 50};
      expect(await service(platform: TargetPlatform.android).check(), isNull);
      play = {'available': true, 'build': 48};
      expect(await service(platform: TargetPlatform.android).check(), isNull);
      play = {'available': true, 'build': 50, 'downloading': true};
      expect(await service(platform: TargetPlatform.android).check(), isNull);
      play = {'available': true, 'build': 50, 'flexible': true};
      final newer = await service(
        platform: TargetPlatform.android,
        release: androidPolicy,
      ).check();
      expect(newer?.notes, '');
      expect(newer?.version, '');
      expect(
        await service(
          platform: TargetPlatform.android,
          release: {...androidPolicy, 'enabled': false},
        ).check(),
        isNull,
      );
    },
  );
  test(
    'Play works if our backend is offline; dev, web and debug checks are skipped',
    () async {
      expect(
        await service(platform: TargetPlatform.android, status: 503).check(),
        isNotNull,
      );
      expect(await service(platform: TargetPlatform.linux).check(), isNull);
      expect(
        await service(platform: TargetPlatform.android, enabled: false).check(),
        isNull,
      );
      expect(
        await service(
          platform: TargetPlatform.android,
          package: PackageInfo(
            appName: 'dev',
            packageName: 'ru.pdd.pdd_app.dev',
            version: '2.1.8',
            buildNumber: '48',
          ),
        ).check(),
        isNull,
      );
    },
  );
  test(
    'coalesced checks and cooldown persist across launches, with no session repeats',
    () async {
      var now = DateTime(2026, 10, 6, 12);
      final app = service(now: () => now);
      final offers = await Future.wait([app.check(), app.check()]);
      final offer = offers.first!;
      expect(identical(offers[0], offers[1]), true);
      expect(await app.shouldShow(offer), true);
      await app.markShown(offer);
      now = now.add(const Duration(days: 2));
      expect(await app.shouldShow(offer), false);
      now = DateTime(2026, 10, 6, 20);
      expect(await service(now: () => now).shouldShow(offer), false);
      now = DateTime(2026, 10, 7, 12);
      expect(await service(now: () => now).shouldShow(offer), true);
    },
  );
  test(
    'download completion offers restart without completing automatically',
    () async {
      play = {'downloaded': true, 'build': 49, 'available': true};
      final app = service(platform: TargetPlatform.android);
      final ready = (await app.check())!;
      expect(ready.readyToInstall, true);
      expect(nativeCalls, ['check']);
      await app.markShown(ready);
      expect(await app.update(ready), true);
      expect(nativeCalls, ['check', 'complete']);
      completeResult = false;
      expect(await app.update(ready), false);
    },
  );
  test(
    'native cancellation never opens store; failed start falls back; iOS opens store',
    () async {
      final urls = <Uri>[];
      final app = service(
        platform: TargetPlatform.android,
        launch: (uri) async {
          urls.add(uri);
          return true;
        },
      );
      final offer = (await app.check())!;
      startResult = 'cancelled';
      expect(await app.update(offer), true);
      expect(urls, isEmpty);
      startResult = 'failed';
      expect(await app.update(offer), true);
      expect(urls.single.host, 'play.google.com');
      final ios = service(
        launch: (uri) async {
          urls.add(uri);
          return false;
        },
      );
      expect(await ios.update((await ios.check())!), false);
      expect(urls.last.host, 'apps.apple.com');
    },
  );
  testWidgets(
    'dialog fits 320px at large text in both themes, with optional dismissal',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final offer = AppUpdateOffer(
        version: '2.1.9',
        notes: List.filled(
          12,
          'Исправления игры и улучшения приложения.',
        ).join(' '),
        packageId: installed.packageName,
        build: 49,
        storeUrl: Uri.parse(policy['storeUrl'] as String),
      );
      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        final key = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: key,
            theme: theme,
            home: Builder(
              builder: (context) => MediaQuery(
                data: const MediaQueryData(
                  size: Size(320, 568),
                  textScaler: TextScaler.linear(2),
                ),
                child: Scaffold(
                  body: Builder(
                    builder: (inner) => TextButton(
                      onPressed: () => AppUpdateDialog.show(inner, offer),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(appL10n.appUpdateAction), findsOneWidget);
        expect(find.text(appL10n.appUpdateLater), findsOneWidget);
        await tester.tap(find.text(appL10n.appUpdateLater));
        await tester.pumpAndSettle();
        expect(find.byType(AppUpdateDialog), findsNothing);
      }
    },
  );
  testWidgets(
    'home defers update under training and rechecks after return; Later survives resume',
    (tester) async {
      final packageReady = Completer<PackageInfo>();
      final app = AppUpdateService.forTesting(
        platform: TargetPlatform.iOS,
        package: () => packageReady.future,
        iosSystemVersion: () async => '26.0',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode(
              request.url.host == 'itunes.apple.com'
                  ? {
                      'results': [listing],
                    }
                  : {'release': policy},
            ),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      final source = ProgressDataSource();
      await source.init();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            progressDataSourceProvider.overrideWithValue(source),
            appUpdateServiceProvider.overrideWithValue(app),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            navigatorKey: navigator,
            navigatorObservers: [appRouteObserver],
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('training in progress')),
          ),
        ),
      );
      packageReady.complete(installed);
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(AppUpdateDialog), findsNothing);
      navigator.currentState!.pop();
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(AppUpdateDialog), findsOneWidget);
      await tester.tap(find.text(appL10n.appUpdateLater));
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(AppUpdateDialog), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Play download event bypasses check cache and restart has its own cooldown',
    (tester) async {
      final app = service(platform: TargetPlatform.android);
      final available = (await app.check())!;
      await app.markShown(available);
      play = {...play!, 'downloaded': true};
      tester.binding.channelBuffers.push(
        'pdd/app_updates',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('downloaded'),
        ),
        (_) {},
      );
      await tester.pump();
      final ready = (await app.check())!;
      expect(ready.readyToInstall, true);
      expect(await app.shouldShow(ready), true);
      expect(nativeCalls.where((method) => method == 'check').length, 2);
      expect(nativeCalls.contains('complete'), false);
    },
  );
}
