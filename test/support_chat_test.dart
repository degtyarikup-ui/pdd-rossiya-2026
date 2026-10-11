import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/support_chat_message.dart';
import 'package:pdd_app/data/services/support_chat_service.dart';
import 'package:pdd_app/presentation/screens/support/support_chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SupportChatMessage Model Tests', () {
    test('Сериализация и десериализация сообщения пользователя', () {
      final msg = SupportChatMessage(
        id: 'msg_123',
        text: 'Здравствуйте! Вопрос по билету 3.',
        sender: SupportMessageSender.user,
        timestamp: 1728600000000,
        authorName: 'Иван',
        status: SupportMessageStatus.sent,
      );

      final json = msg.toJson();
      expect(json['id'], 'msg_123');
      expect(json['text'], 'Здравствуйте! Вопрос по билету 3.');
      expect(json['sender'], 'user');
      expect(json['ts'], 1728600000000);
      expect(json['authorName'], 'Иван');
      expect(json['status'], 'sent');

      final fromJson = SupportChatMessage.fromJson(json);
      expect(fromJson.id, msg.id);
      expect(fromJson.text, msg.text);
      expect(fromJson.isUser, isTrue);
      expect(fromJson.isSupport, isFalse);
      expect(fromJson.timestamp, msg.timestamp);
      expect(fromJson.authorName, msg.authorName);
      expect(fromJson.status, SupportMessageStatus.sent);
    });

    test('Сериализация и десериализация ответа поддержки', () {
      final msg = SupportChatMessage(
        id: 'tg_999',
        text: 'Добрый день! Разобрались, исправили.',
        sender: SupportMessageSender.support,
        timestamp: 1728600050000,
        authorName: 'Поддержка',
        status: SupportMessageStatus.sent,
      );

      final json = msg.toJson();
      expect(json['sender'], 'support');

      final fromJson = SupportChatMessage.fromJson(json);
      expect(fromJson.isSupport, isTrue);
      expect(fromJson.isUser, isFalse);
      expect(fromJson.text, msg.text);
      expect(fromJson.authorName, 'Поддержка');
    });

    test('copyWith обновляет поля без мутации оригинала', () {
      final original = SupportChatMessage(
        id: 'temp_1',
        text: 'Тест',
        sender: SupportMessageSender.user,
        timestamp: 1000,
        status: SupportMessageStatus.sending,
      );

      final updated = original.copyWith(
        id: 'server_1',
        status: SupportMessageStatus.sent,
      );

      expect(updated.id, 'server_1');
      expect(updated.status, SupportMessageStatus.sent);
      expect(updated.text, 'Тест');
      expect(original.id, 'temp_1');
      expect(original.status, SupportMessageStatus.sending);
    });
  });

  group('SupportChatService Storage Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Генерация и сохранение уникального clientId', () async {
      final service = SupportChatService.instance;
      final id1 = await service.getClientId();
      expect(id1, isNotEmpty);
      expect(id1.startsWith('guest_'), isTrue);

      final id2 = await service.getClientId();
      expect(id2, equals(id1));
    });

    test('Кэширование и чтение сообщений из SharedPreferences', () async {
      final service = SupportChatService.instance;
      final messages = [
        SupportChatMessage(
          id: '1',
          text: 'Сообщение 1',
          sender: SupportMessageSender.user,
          timestamp: 1000,
        ),
        SupportChatMessage(
          id: '2',
          text: 'Ответ 1',
          sender: SupportMessageSender.support,
          timestamp: 2000,
        ),
      ];

      await service.saveCachedMessages(messages);
      final loaded = await service.loadCachedMessages();

      expect(loaded.length, 2);
      expect(loaded[0].id, '1');
      expect(loaded[0].text, 'Сообщение 1');
      expect(loaded[1].id, '2');
      expect(loaded[1].text, 'Ответ 1');
      expect(loaded[1].isSupport, isTrue);
    });
  });

  group('SupportChatScreen Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('Отображение экрана поддержки и элементов управления', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SupportChatScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Проверяем наличие поля ввода и иконки отправки
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.byIcon(Icons.support_agent_rounded), findsWidgets);
    });
  });
}
