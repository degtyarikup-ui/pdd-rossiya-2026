import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/presentation/widgets/support_chat_message_text.dart';

void main() {
  group('parseChatLinks & URL normalization tests', () {
    test('Обычный текст без ссылок', () {
      const text = 'Здравствуйте, у меня вопрос по билету 5.';
      final parts = parseChatLinks(text);
      expect(parts.length, 1);
      expect(parts.first.isLink, isFalse);
      expect(parts.first.text, text);
      expect(parts.first.url, isNull);
    });

    test('Markdown-ссылки [Текст](url)', () {
      const text =
          'Перейдите на [наш сайт](https://pdd-drive.online/pay) для оплаты.';
      final parts = parseChatLinks(text);
      expect(parts.length, 3);
      expect(parts[0].isLink, isFalse);
      expect(parts[0].text, 'Перейдите на ');
      expect(parts[1].isLink, isTrue);
      expect(parts[1].text, 'наш сайт');
      expect(parts[1].url, 'https://pdd-drive.online/pay');
      expect(parts[2].isLink, isFalse);
      expect(parts[2].text, ' для оплаты.');
    });

    test('Прямые HTTPS/HTTP ссылки', () {
      const text = 'Ссылка: https://pdd-drive.online и http://test.com/path';
      final parts = parseChatLinks(text);
      expect(parts.length, 4);
      expect(parts[0].text, 'Ссылка: ');
      expect(parts[1].isLink, isTrue);
      expect(parts[1].text, 'https://pdd-drive.online');
      expect(parts[1].url, 'https://pdd-drive.online');
      expect(parts[2].text, ' и ');
      expect(parts[3].isLink, isTrue);
      expect(parts[3].text, 'http://test.com/path');
      expect(parts[3].url, 'http://test.com/path');
    });

    test('Ссылки без схемы: www. и t.me/', () {
      const text = 'Сайт www.gibdd.ru или канал t.me/pdd_russia';
      final parts = parseChatLinks(text);
      expect(parts.length, 4);
      expect(parts[0].text, 'Сайт ');
      expect(parts[1].isLink, isTrue);
      expect(parts[1].text, 'www.gibdd.ru');
      expect(parts[1].url, 'https://www.gibdd.ru');
      expect(parts[2].text, ' или канал ');
      expect(parts[3].isLink, isTrue);
      expect(parts[3].text, 't.me/pdd_russia');
      expect(parts[3].url, 'https://t.me/pdd_russia');
    });

    test('Домены верхнего уровня без схемы', () {
      const text = 'Подробнее на pdd-drive.online/tarify прямо сейчас.';
      final parts = parseChatLinks(text);
      expect(parts.length, 3);
      expect(parts[0].text, 'Подробнее на ');
      expect(parts[1].isLink, isTrue);
      expect(parts[1].text, 'pdd-drive.online/tarify');
      expect(parts[1].url, 'https://pdd-drive.online/tarify');
      expect(parts[2].text, ' прямо сейчас.');
    });

    test('Email-адреса распознаются как mailto:', () {
      const text = 'Напишите нам: support@pdd-drive.online.';
      final parts = parseChatLinks(text);
      expect(parts.length, 3);
      expect(parts[0].text, 'Напишите нам: ');
      expect(parts[1].isLink, isTrue);
      expect(parts[1].text, 'support@pdd-drive.online');
      expect(parts[1].url, 'mailto:support@pdd-drive.online');
      expect(parts[2].text, '.');
    });

    test('email whose mailbox looks like a domain still opens mail', () {
      final parts = parseChatLinks('ivan.ru@example.com');
      expect(parts, const [
        LinkSpanInfo(
          text: 'ivan.ru@example.com',
          url: 'mailto:ivan.ru@example.com',
        ),
      ]);
    });

    test(
      'markdown links keep balanced URL parentheses in chat and previews',
      () {
        const url = 'https://en.wikipedia.org/wiki/Car_(automobile)';
        const message = 'Read [the article]($url).';
        expect(parseChatLinks(message), const [
          LinkSpanInfo(text: 'Read '),
          LinkSpanInfo(text: 'the article', url: url),
          LinkSpanInfo(text: '.'),
        ]);
        expect(stripMarkdownLinks(message), 'Read the article.');
      },
    );

    test('Отделение знаков препинания на конце ссылки', () {
      final tests = [
        ('https://site.ru.', 'https://site.ru', '.'),
        ('https://site.ru,', 'https://site.ru', ','),
        ('https://site.ru;', 'https://site.ru', ';'),
        ('https://site.ru!', 'https://site.ru', '!'),
        ('https://site.ru?', 'https://site.ru', '?'),
        ('(https://site.ru)', 'https://site.ru', ')'),
      ];

      for (final (input, expectedUrl, expectedTrailing) in tests) {
        final parts = parseChatLinks(input);
        final link = parts.firstWhere((p) => p.isLink);
        expect(link.text, expectedUrl);
        expect(link.url, expectedUrl);
        expect(parts.last.text, endsWith(expectedTrailing));
      }
    });

    test('Скобки внутри URL не обрезаются при балансе', () {
      const text = 'https://en.wikipedia.org/wiki/Car_(automobile) статья';
      final parts = parseChatLinks(text);
      expect(parts.first.isLink, isTrue);
      expect(
        parts.first.text,
        'https://en.wikipedia.org/wiki/Car_(automobile)',
      );
      expect(parts.first.url, 'https://en.wikipedia.org/wiki/Car_(automobile)');
      expect(parts.last.text, ' статья');
    });

    test('stripMarkdownLinks корректно очищает markdown-ссылки', () {
      expect(
        stripMarkdownLinks('Посетите [наш сайт](https://pdd-drive.online)!'),
        'Посетите наш сайт!',
      );
      expect(stripMarkdownLinks('Обычный текст'), 'Обычный текст');
    });

    test('normalizeChatUrl добавляет https:// при отсутствии схемы', () {
      expect(normalizeChatUrl('pdd-drive.online'), 'https://pdd-drive.online');
      expect(normalizeChatUrl('www.google.com'), 'https://www.google.com');
      expect(normalizeChatUrl('https://site.ru'), 'https://site.ru');
      expect(normalizeChatUrl('mailto:test@ya.ru'), 'mailto:test@ya.ru');
    });
  });

  group('SupportChatMessageText Widget Tests', () {
    testWidgets('Отображение обычного текста', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SupportChatMessageText(
              text: 'Привет, как дела?',
              isUser: false,
            ),
          ),
        ),
      );

      expect(find.byType(RichText), findsOneWidget);
      final richText = tester.widget<RichText>(find.byType(RichText));
      expect(richText.text.toPlainText(), 'Привет, как дела?');
    });

    testWidgets('Клик по ссылке вызывает onTapUrl', (tester) async {
      String? openedUrl;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SupportChatMessageText(
              text: 'Наш сайт: https://pdd-drive.online!',
              isUser: false,
              onTapUrl: (url) {
                openedUrl = url;
              },
            ),
          ),
        ),
      );

      final richTextFinder = find.descendant(
        of: find.byType(SupportChatMessageText),
        matching: find.byType(RichText),
      );
      expect(richTextFinder, findsOneWidget);

      final richText = tester.widget<RichText>(richTextFinder);
      TextSpan? foundLinkSpan;
      richText.text.visitChildren((span) {
        if (span is TextSpan && span.text == 'https://pdd-drive.online') {
          foundLinkSpan = span;
          return false;
        }
        return true;
      });
      expect(foundLinkSpan, isNotNull);
      final linkSpan = foundLinkSpan!;

      expect(linkSpan.recognizer, isNotNull);
      expect(linkSpan.style?.decoration, TextDecoration.underline);

      // Эмулируем тап по ссылке
      (linkSpan.recognizer as dynamic).onTap();
      await tester.pump();

      expect(openedUrl, 'https://pdd-drive.online');
    });

    testWidgets('Клик по markdown-ссылке вызывает onTapUrl с target URL', (
      tester,
    ) async {
      String? openedUrl;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SupportChatMessageText(
              text:
                  'Посетите [Оплату](https://pdd-drive.online/pay) пожалуйста.',
              isUser: true,
              onTapUrl: (url) {
                openedUrl = url;
              },
            ),
          ),
        ),
      );

      final richTextFinder = find.descendant(
        of: find.byType(SupportChatMessageText),
        matching: find.byType(RichText),
      );
      final richText = tester.widget<RichText>(richTextFinder);
      TextSpan? foundLink;
      richText.text.visitChildren((child) {
        if (child is TextSpan && child.text == 'Оплату') {
          foundLink = child;
          return false;
        }
        return true;
      });

      expect(foundLink, isNotNull);
      final linkSpan = foundLink!;

      expect(linkSpan.style?.color, Colors.white);
      expect(linkSpan.style?.decoration, TextDecoration.underline);

      (linkSpan.recognizer as dynamic).onTap();
      await tester.pump();

      expect(openedUrl, 'https://pdd-drive.online/pay');
    });

    testWidgets('Различные цвета для сообщений пользователя и поддержки', (
      tester,
    ) async {
      // Сообщение оператора
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SupportChatMessageText(
              text: 'Ссылка: https://pdd-drive.online',
              isUser: false,
            ),
          ),
        ),
      );

      final supportRichTextFinder = find.descendant(
        of: find.byType(SupportChatMessageText),
        matching: find.byType(RichText),
      );
      final supportRichText = tester.widget<RichText>(supportRichTextFinder);
      TextSpan? foundSupportLink;
      supportRichText.text.visitChildren((child) {
        if (child is TextSpan && child.text == 'https://pdd-drive.online') {
          foundSupportLink = child;
          return false;
        }
        return true;
      });
      expect(foundSupportLink, isNotNull);
      final supportLink = foundSupportLink!;

      // Для оператора цвет ссылки — акцентный (brand blue)
      expect(supportLink.style?.color, AppThemeColors.light.accent);

      // Сообщение пользователя
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SupportChatMessageText(
              text: 'Ссылка: https://pdd-drive.online',
              isUser: true,
            ),
          ),
        ),
      );

      final userRichTextFinder = find.descendant(
        of: find.byType(SupportChatMessageText),
        matching: find.byType(RichText),
      );
      final userRichText = tester.widget<RichText>(userRichTextFinder);
      TextSpan? foundUserLink;
      userRichText.text.visitChildren((child) {
        if (child is TextSpan && child.text == 'https://pdd-drive.online') {
          foundUserLink = child;
          return false;
        }
        return true;
      });
      expect(foundUserLink, isNotNull);
      final userLink = foundUserLink!;

      // Для пользователя цвет ссылки — белый (чтобы читался на синей плашке)
      expect(userLink.style?.color, Colors.white);
    });

    testWidgets('Несколько ссылок в одном сообщении открывают свои адреса', (
      tester,
    ) async {
      final openedUrls = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SupportChatMessageText(
              text: 'Сайт 1: https://first.com, сайт 2: https://second.com.',
              isUser: false,
              onTapUrl: (url) {
                openedUrls.add(url);
              },
            ),
          ),
        ),
      );

      final richTextFinder = find.descendant(
        of: find.byType(SupportChatMessageText),
        matching: find.byType(RichText),
      );
      final richText = tester.widget<RichText>(richTextFinder);
      final links = <TextSpan>[];
      richText.text.visitChildren((child) {
        if (child is TextSpan &&
            (child.text == 'https://first.com' ||
                child.text == 'https://second.com')) {
          links.add(child);
        }
        return true;
      });

      expect(links.length, 2);
      final link1 = links[0];
      final link2 = links[1];

      (link1.recognizer as dynamic).onTap();
      (link2.recognizer as dynamic).onTap();
      await tester.pump();

      expect(openedUrls, ['https://first.com', 'https://second.com']);
    });
  });
}
