import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/config/store_config.dart';
import 'package:pdd_app/data/services/acquisition_fields.dart';
import 'package:pdd_app/data/services/acquisition_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Play referrer preserves source and campaign without mixing store', () {
    final fields = AcquisitionService.parseReferrer(
      'utm_source=threads&utm_campaign=launch_48&utm_medium=social',
      'play_referrer',
    );
    expect(fields['marketingSource'], 'threads');
    expect(fields['marketingCampaign'], 'launch_48');
    expect(fields['attributionMethod'], 'play_referrer');
    expect(fields['marketingMedium'], 'social');
    expect(fields.containsKey('source'), isFalse);
  });
  test('organic and invalid sources never turn into a Threads attribution', () {
    expect(
      AcquisitionService.parseReferrer(
        'utm_source=google-play',
        'play_referrer',
      ),
      isEmpty,
    );
    expect(
      AcquisitionService.parseReferrer('utm_source=__proto__', 'play_referrer'),
      isEmpty,
    );
    expect(
      AcquisitionService.parseReferrer(
        'utm_source=th&utm_campaign=%3Cscript%3E',
        'play_referrer',
      ),
      {'marketingSource': 'threads', 'attributionMethod': 'play_referrer'},
    );
  });

  test('Play organic stays separate from web Google and unmarked installs', () {
    expect(
      AcquisitionService.parseReferrer(
        'utm_source=google-play&utm_medium=organic',
        'play_referrer',
      ),
      {
        'marketingSource': 'google_play_organic',
        'marketingMedium': 'organic',
        'attributionMethod': 'play_organic',
      },
    );
    expect(AcquisitionService.parseReferrer('', 'play_referrer'), isEmpty);
    expect(
      AcquisitionService.parseReferrer(
        'utm_source=google_play_organic',
        'web_utm',
      ),
      isEmpty,
    );
  });

  test('RuStore referrals retain source and do not invent organic search', () {
    final fields = AcquisitionService.parseReferrer(
      'utm_source=threads&utm_campaign=launch&utm_medium=social',
      'rustore_referrer',
    );
    expect(fields['marketingSource'], 'threads');
    expect(fields['attributionMethod'], 'rustore_referrer');
    expect(
      AcquisitionService.parseReferrer(
        'utm_source=google-play&utm_medium=organic',
        'rustore_referrer',
      ),
      isEmpty,
    );
  });

  test('article context passes store referrer without URL secrets', () {
    final fields = AcquisitionService.parseReferrer(
      'utm_source=yandex&utm_medium=organic&utm_content=article_cta&'
          'landing_page=%2Fblog%2Fexam%2F%3Ftoken%3Dsecret&'
          'referrer_host=yandex.ru',
      'play_referrer',
    );
    expect(fields['marketingSource'], 'yandex');
    expect(fields['marketingMedium'], 'organic');
    expect(fields['marketingContent'], 'article_cta');
    expect(fields['landingPage'], '/blog/exam/');
    expect(fields['referrerHost'], 'yandex.ru');
    expect(fields.toString(), isNot(contains('secret')));
  });

  test('search and AI referrers are recognized with domain boundaries', () {
    for (final entry in {
      'https://yandex.by/search/': 'yandex',
      'https://www.google.ru/search?q=test': 'google',
      'https://www.google.com.au/search?q=test': 'google',
      'https://www.bing.com/search': 'bing',
      'https://duckduckgo.com/': 'duckduckgo',
      'https://gemini.google.com/': 'gemini',
      'https://chatgpt.com/': 'chatgpt',
      'https://www.google.com.evil.example/': 'other',
    }.entries) {
      final fields = AcquisitionFields.fromBrowser(
        Uri.parse('https://pdd-drive.ru/app/'),
        entry.key,
      );
      expect(fields['marketingSource'], entry.value, reason: entry.key);
    }
  });

  test('own pages and OAuth return do not become new search acquisitions', () {
    for (final referrer in [
      'https://pdd-drive.ru/blog/exam/',
      'https://app.pdd-drive.ru/',
      'https://accounts.google.com/o/oauth2/',
      'https://oauth.yandex.ru/authorize',
      'https://appleid.apple.com/auth/authorize',
    ]) {
      final fields = AcquisitionFields.fromBrowser(
        Uri.parse('https://pdd-drive.ru/app/?code=secret&state=private'),
        referrer,
      );
      expect(fields['marketingSource'], 'direct');
      expect(fields['landingPage'], '/app/');
      expect(fields.containsKey('referrerHost'), isFalse);
      expect(fields.toString(), isNot(contains('secret')));
    }
  });

  test('forwarded article tags survive internal app entry', () {
    final fields = AcquisitionFields.fromBrowser(
      Uri.parse(
        'https://pdd-drive.ru/app/?utm_source=google&utm_medium=organic&'
        'landing_page=%2Fblog%2Fexam%2F&referrer_host=www.google.com',
      ),
      'https://pdd-drive.ru/blog/exam/',
    );
    expect(fields['marketingSource'], 'google');
    expect(fields['landingPage'], '/blog/exam/');
    expect(fields['referrerHost'], 'www.google.com');
  });

  test('an explicit Google campaign is not assumed to be organic search', () {
    final fields = AcquisitionFields.fromBrowser(
      Uri.parse('https://pdd-drive.ru/app/?utm_source=google'),
      '',
    );
    expect(fields['marketingMedium'], 'referral');
    expect(
      AcquisitionFields.fromBrowser(
        Uri.parse('https://pdd-drive.ru/app/'),
        '',
      )['marketingMedium'],
      'direct',
    );
  });

  test('bad fields are discarded while valid source remains available', () {
    final fields = AcquisitionService.parseReferrer(
      'utm_source=th&utm_campaign=constructor&'
          'landing_page=%2F%2Fevil.example&referrer_host=bad%40example.com',
      'play_referrer',
    );
    expect(fields, {
      'marketingSource': 'threads',
      'attributionMethod': 'play_referrer',
    });
    expect(
      AcquisitionService.parseReferrer('utm_source=%ZZ', 'play_referrer'),
      isEmpty,
    );
    expect(AcquisitionFields.path('/${'x' * 241}'), isEmpty);
  });

  group('saved first acquisition', () {
    const channel = MethodChannel('pdd/acquisition');
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AcquisitionService.resetForTesting();
      SharedPreferences.setMockInitialValues({});
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      AcquisitionService.resetForTesting();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('source and article remain first touch across launches', () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            calls++;
            return calls == 1
                ? 'utm_source=yandex&utm_medium=organic&landing_page=%2Fblog%2Fexam%2F'
                : 'utm_source=instagram';
          });
      final first = await AcquisitionService.fields();
      AcquisitionService.resetForTesting();
      expect(await AcquisitionService.fields(), first);
      expect(first['marketingSource'], 'yandex');
      expect(first['landingPage'], '/blog/exam/');
      expect(calls, 1);
    });

    test('reads only the referrer API selected for the build store', () async {
      String? method;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            method = call.method;
            return 'utm_source=threads';
          });
      final fields = await AcquisitionService.fields();
      final rustore = StoreConfig.current == AppStore.rustore;
      expect(method, rustore ? 'rustoreInstallReferrer' : 'installReferrer');
      expect(
        fields['attributionMethod'],
        rustore ? 'rustore_referrer' : 'play_referrer',
      );
    });

    test('legacy first source stays immutable', () async {
      SharedPreferences.setMockInitialValues({
        'acquisition_v1': jsonEncode({
          'marketingSource': 'threads',
          'marketingCampaign': 'launch',
          'attributionMethod': 'play_referrer',
        }),
      });
      final first = await AcquisitionService.fields();
      expect(first['marketingSource'], 'threads');
      expect(first['marketingCampaign'], 'launch');
    });

    test('corrupt preference does not swallow current referral', () async {
      SharedPreferences.setMockInitialValues({'acquisition_v1': '{broken'});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => 'utm_source=instagram',
          );
      expect(
        (await AcquisitionService.fields())['marketingSource'],
        'instagram',
      );
    });
  });
}
