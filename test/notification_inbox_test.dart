import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/notification_inbox_service.dart';
import 'package:pdd_app/data/services/remote_notifications_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/notifications/notifications_screen.dart';
import 'package:pdd_app/presentation/widgets/notifications_bell_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mutable account/Premium state the inbox observes.
class _State {
  bool premium = false;
  DateTime? until;
  String? user = 'google_1';
  bool sbp = false;
  DateTime now = DateTime(2026, 10, 28, 12);
}

NotificationInboxService _inbox(_State s) =>
    NotificationInboxService.forTesting(
      premium: () => s.premium,
      premiumUntil: () => s.until,
      userId: () => s.user,
      sbpAvailable: () async => s.sbp,
      now: () => s.now,
    );

AppNotice _news(String id, {String kind = 'news', int day = 20}) => AppNotice(
  id: id,
  title: 'Новые вопросы',
  body: 'Добавили разборы',
  kind: kind,
  createdAt: DateTime(2026, 10, day),
  expiresAt: DateTime(2026, 12, 1),
);

const _id1 = 'c069e042-5b7b-40a0-b15e-b80c4444ce1d';
const _id2 = 'd169e042-5b7b-40a0-b15e-b80c4444ce1d';

void main() {
  setUpAll(initAppDateFormatting);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Premium start, extension and end are reported once each', () async {
    final s = _State()
      ..premium = true
      ..until = DateTime(2026, 11, 4);
    final inbox = _inbox(s);
    await inbox.init();
    await inbox.refresh();
    expect(inbox.items.map((i) => i.type), [InboxItemType.premiumStarted]);
    expect(inbox.items.single.premiumUntil, DateTime(2026, 11, 4));

    // Same date again: nothing new.
    await inbox.refresh();
    expect(inbox.items, hasLength(1));

    // Renewal adds a second "started" entry with the new date.
    s.until = DateTime(2027, 2, 2);
    await inbox.refresh();
    expect(inbox.items, hasLength(2));

    // Expiry, observed after the server no longer reports the date.
    s
      ..premium = false
      ..until = null
      ..now = DateTime(2027, 2, 3);
    await inbox.refresh();
    expect(inbox.items.first.type, InboxItemType.premiumEnded);
    expect(inbox.items.first.premiumUntil, DateTime(2027, 2, 2));
    await inbox.refresh();
    expect(
      inbox.items.where((i) => i.type == InboxItemType.premiumEnded),
      hasLength(1),
    );
  });

  test(
    'signing out is not the end of Premium; history is per account',
    () async {
      final s = _State()
        ..premium = true
        ..until = DateTime(2026, 11, 4);
      final inbox = _inbox(s);
      await inbox.init();
      await inbox.refresh();

      s
        ..premium = false
        ..user = null;
      await inbox.refresh();
      expect(inbox.items, isEmpty, reason: 'guest sees no account history');

      s.user = 'yandex_2';
      await inbox.refresh();
      expect(inbox.items, isEmpty);

      // Back to the first account before expiry: no "ended", same start entry.
      s
        ..user = 'google_1'
        ..premium = true;
      await inbox.refresh();
      expect(inbox.items.map((i) => i.type), [InboxItemType.premiumStarted]);
    },
  );

  test(
    'SBP entry only without Premium and when payments are available',
    () async {
      final s = _State()..sbp = true;
      final inbox = _inbox(s);
      await inbox.init();
      await inbox.refresh();
      expect(inbox.items.map((i) => i.type), [InboxItemType.sbp]);

      s
        ..premium = true
        ..until = DateTime(2026, 11, 4);
      await inbox.refresh();
      expect(inbox.items.map((i) => i.type), [InboxItemType.premiumStarted]);

      final unavailable = _inbox(
        _State()
          ..sbp = false
          ..user = 'vk_3',
      );
      await unavailable.init();
      await unavailable.refresh();
      expect(unavailable.items, isEmpty);
    },
  );

  test(
    'unread state: shown windows count as read, markAllRead persists',
    () async {
      final s = _State();
      final inbox = _inbox(s);
      await inbox.init();
      inbox.setNews([_news(_id1, day: 21), _news(_id2, kind: 'popup')], {_id2});
      expect(inbox.items.first.notice!.id, _id1, reason: 'newest first');
      expect(inbox.unreadCount, 1);

      await inbox.markAllRead();
      expect(inbox.hasUnread, isFalse);

      final again = _inbox(s);
      await again.init();
      again.setNews([_news(_id1, day: 21)], const {});
      expect(again.hasUnread, isFalse, reason: 'read marks survive restart');
    },
  );

  testWidgets('bell shows a badge until the inbox is opened', (tester) async {
    final s = _State();
    final inbox = _inbox(s);
    await tester.runAsync(inbox.init);
    inbox.setNews([_news(_id1)], const {});

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: NotificationsBellButton(service: inbox)),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('inbox-unread-badge')), findsOneWidget);

    await tester.tap(find.byType(NotificationsBellButton));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.text('Новые вопросы'), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-fresh-dot')), findsOneWidget);
    expect(inbox.hasUnread, isFalse);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inbox-unread-badge')), findsNothing);
  });

  test('news are never shown as a popup window', () {
    final news = AppNotice.parse({
      'id': _id1,
      'kind': 'news',
      'title': 'Оплата по СБП',
      'body': 'Теперь доступна',
      'expiresAt': DateTime(2026, 12, 1).millisecondsSinceEpoch,
      'createdAt': DateTime(2026, 10, 1).millisecondsSinceEpoch,
      'action': 'premium',
    })!;
    expect(news.isNews, isTrue);
    expect(news.action, NoticeAction.premium);
    expect(news.createdAt, DateTime(2026, 10, 1));
    expect(appL10n.inboxTitle, isNotEmpty);
  });
}
