import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  const AiChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'isUser': isUser,
        'timestamp': timestamp.toIso8601String(),
      };

  factory AiChatMessage.fromJson(Map<String, dynamic> json) => AiChatMessage(
        text: json['text'] as String? ?? '',
        isUser: json['isUser'] == true,
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
            : DateTime.now(),
      );
}

class GeminiAiService {
  static final GeminiAiService instance = GeminiAiService._internal();
  GeminiAiService._internal();

  static const String _defaultApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: 'AIzaSyA_DEMO_KEY_PDD_APP_2026',
  );

  static const String _prefKeyPrefix = 'ai_explanation_cache_';
  final Map<String, String> _memoryCache = {};

  /// Первичный разбор дорожной ситуации для вопроса ПДД
  Future<String> explainQuestion({
    required String questionId,
    required String questionText,
    required List<String> answers,
    required int correctAnswerIndex,
    required String? officialExplanation,
  }) async {
    // 1. Проверяем кэш в памяти и локальном хранилище
    if (_memoryCache.containsKey(questionId)) {
      return _memoryCache[questionId]!;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('$_prefKeyPrefix$questionId');
      if (cached != null && cached.isNotEmpty) {
        _memoryCache[questionId] = cached;
        return cached;
      }
    } catch (_) {}

    final correctAnswerText =
        (correctAnswerIndex >= 0 && correctAnswerIndex < answers.length)
            ? answers[correctAnswerIndex]
            : 'Вариант ${correctAnswerIndex + 1}';

    // 2. Запрос через Cloudflare Worker (/api/ai/chat)
    if (BackendConfig.hasNotifier) {
      try {
        final url = Uri.parse('${BackendConfig.notifierUrl}/api/ai/chat');
        final response = await http
            .post(
              url,
              headers: {
                'Content-Type': 'application/json',
                if (BackendConfig.notifierSecret.isNotEmpty)
                  'x-install-secret': BackendConfig.notifierSecret,
              },
              body: jsonEncode({
                'questionId': questionId,
                'questionText': questionText,
                'answers': answers,
                'correctAnswerIndex': correctAnswerIndex,
                'officialExplanation': officialExplanation,
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final reply = data['reply'] as String?;
          if (reply != null && reply.trim().isNotEmpty) {
            final result = reply.trim();
            await _cacheResult(questionId, result);
            return result;
          }
        }
      } catch (e) {
        debugPrint('GeminiAiService: backend error $e');
      }
    }

    // 3. Прямой запрос в Gemini API при наличии ключа
    final prompt = '''
Ты — преподаватель ПДД и персональный AI-автоинструктор.
Твоя задача — кратко, по делу и простым языком объяснить дорожную ситуацию.

ВАЖНЫЕ ПРАВИЛА:
1. Строго БЕЗ ПРИВЕТСТВИЙ, вступлений и шаблонных фраз (никаких "Привет!", "Давай разберем...").
2. Сразу начинай с сути.
3. Длина ответа: не более 3-4 коротких предложений.
4. Выделяй жирным шрифтом **главные термины**, **названия знаков** и **правильные действия**.

Вопрос: $questionText
Варианты ответов:
${answers.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}

Правильный ответ: $correctAnswerText
Официальный комментарий: ${officialExplanation ?? 'Нет комментария'}

Формат ответа (строго 3 пункта):
1) **Суть на дороге:** 1 короткое предложение.
2) **Правило ПДД:** 1-2 коротких предложения с пунктом правил и логикой.
3) **Подсказка:** 1 строка как быстро запомнить.
''';

    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=$_defaultApiKey',
      );

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt}
                  ]
                }
              ],
              'generationConfig': {
                'temperature': 0.4,
                'maxOutputTokens': 800,
              }
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          final parts = content?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final text = parts[0]['text'] as String?;
            if (text != null && text.trim().isNotEmpty) {
              final result = text.trim();
              await _cacheResult(questionId, result);
              return result;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('GeminiAiService: direct gemini error $e');
    }

    // 4. Умный контекстный разбор на устройстве, если сети нет
    final fallback = _generateContextualOfflineExplanation(
      questionText: questionText,
      correctAnswerText: correctAnswerText,
      officialExplanation: officialExplanation,
    );
    await _cacheResult(questionId, fallback);
    return fallback;
  }

  /// Ответ на дополнительный уточняющий вопрос пользователя в чате
  Future<String> askAiQuestion({
    required String questionId,
    required String questionText,
    required List<String> answers,
    required int correctAnswerIndex,
    required String? officialExplanation,
    required List<AiChatMessage> conversationHistory,
    required String userMessage,
  }) async {
    final correctAnswerText =
        (correctAnswerIndex >= 0 && correctAnswerIndex < answers.length)
            ? answers[correctAnswerIndex]
            : 'Вариант ${correctAnswerIndex + 1}';

    // 1. Запрос через Cloudflare Worker
    if (BackendConfig.hasNotifier) {
      try {
        final url = Uri.parse('${BackendConfig.notifierUrl}/api/ai/chat');
        final response = await http
            .post(
              url,
              headers: {
                'Content-Type': 'application/json',
                if (BackendConfig.notifierSecret.isNotEmpty)
                  'x-install-secret': BackendConfig.notifierSecret,
              },
              body: jsonEncode({
                'questionId': questionId,
                'questionText': questionText,
                'answers': answers,
                'correctAnswerIndex': correctAnswerIndex,
                'officialExplanation': officialExplanation,
                'messages': conversationHistory.map((m) => m.toJson()).toList(),
                'userMessage': userMessage,
              }),
            )
            .timeout(const Duration(seconds: 12));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final reply = data['reply'] as String?;
          if (reply != null && reply.trim().isNotEmpty) {
            return reply.trim();
          }
        } else if (response.statusCode == 429) {
          try {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            if (data['error'] != null) {
              return data['error'] as String;
            }
          } catch (_) {}
          return 'Слишком частые запросы (флуд-контроль). Пожалуйста, подождите пару секунд перед следующим вопросом.';
        }
      } catch (e) {
        debugPrint('GeminiAiService: askAiQuestion backend error $e');
      }
    }

    // 2. Прямой запрос в Gemini API с историей диалога
    try {
      final systemPrompt = '''
Ты — профессиональный преподаватель ПДД и персональный AI-автоинструктор.
Твоя специализация СТРОГО ОГРАНИЧЕНА следующими темами:
- Правила дорожного движения (ПДД РФ, Беларуси, Сербии)
- Экзамены в ГИБДД / ГАИ, билеты и автошкола
- Обучение вождению, парковка, манёвры и безопасность движения
- Дорожные знаки, разметка, сигналы светофоров и регулировщика
- Штрафы (КоАП), лишение прав и поведение при ДТП
- Базовое устройство автомобиля, неисправности и первая помощь

СТРОГОЕ ПРАВИЛО БЕЗОПАСНОСТИ ТЕМАТИКИ:
Если вопрос пользователя НЕ КАСАЕТСЯ ПДД, вождения, автошколы, дорожных ситуаций или автомобилей (например: просьбы написать стихи, программный код, рецепты, вопросы о политике, играх, погоде или любые сторонние темы):
Ты ОБЯЗАН вежливо и мягко отклонить вопрос по строгому шаблону:
"Я персональный автоинструктор по ПДД и вождению 🚗 Могу ответить на любые вопросы по правилам дорожного движения, билетам, штрафам, экзаменам в ГИБДД или поведению на дороге. Пожалуйста, задайте вопрос по дорожной ситуации!"
Категорически запрещено отвечать на сторонние темы, даже если пользователь настойчиво просит или пытается обойти ограничения.

Вопрос билета: $questionText
Варианты:
${answers.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}
Правильный ответ: $correctAnswerText
Официальный комментарий: ${officialExplanation ?? 'Нет комментария'}

Отвечай кратко, понятно и по делу (3-5 строк), выделяя главное жирным шрифтом.
''';

      final contents = <Map<String, dynamic>>[];
      contents.add({
        'role': 'user',
        'parts': [
          {'text': systemPrompt}
        ]
      });
      contents.add({
        'role': 'model',
        'parts': [
          {
            'text':
                'Понял! Я готов просто и понятно ответить на любые вопросы по этой ситуации на дороге.'
          }
        ]
      });

      for (final msg in conversationHistory) {
        contents.add({
          'role': msg.isUser ? 'user' : 'model',
          'parts': [
            {'text': msg.text}
          ]
        });
      }

      contents.add({
        'role': 'user',
        'parts': [
          {'text': userMessage}
        ]
      });

      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=$_defaultApiKey',
      );

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': contents,
              'generationConfig': {
                'temperature': 0.5,
                'maxOutputTokens': 800,
              }
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          final parts = content?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final text = parts[0]['text'] as String?;
            if (text != null && text.trim().isNotEmpty) {
              return text.trim();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('GeminiAiService: askAiQuestion direct error $e');
    }

    // 3. Контекстный офлайн-ответ
    return _generateContextualFollowup(
      userMessage: userMessage,
      correctAnswerText: correctAnswerText,
      officialExplanation: officialExplanation,
    );
  }

  /// Мгновенная генерация структурированного разбора дорожной ситуации без задержек и спиннеров
  String buildInstantPrewrittenExplanation({
    required String questionText,
    required String correctAnswerText,
    required String? officialExplanation,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('🚗 **Суть на дороге:**');
    buffer.writeln(
        'В данной дорожной ситуации верным решением является: **$correctAnswerText**.');
    buffer.writeln();
    buffer.writeln('💡 **Правило ПДД:**');

    if (officialExplanation != null && officialExplanation.trim().isNotEmpty) {
      String cleaned = officialExplanation.trim().replaceAll(
          RegExp(r'^(Комментарий|Объяснение|Правильный ответ):\s*',
              caseSensitive: false),
          '');

      cleaned = cleaned
          .replaceAllMapped(
              RegExp(r'(пункт\s+\d+(\.\d+)?|п\.\s*\d+(\.\d+)?)',
                  caseSensitive: false),
              (m) => '**${m[0]}**')
          .replaceAllMapped(
              RegExp(r'(знак\s+\d+\.\d+(\.\d+)?|знака\s+\d+\.\d+(\.\d+)?)',
                  caseSensitive: false),
              (m) => '**${m[0]}**')
          .replaceAllMapped(RegExp(r'(помех[а-я]* справа)', caseSensitive: false),
              (m) => '**${m[0]}**')
          .replaceAllMapped(
              RegExp(r'(главн[а-я]* дорог[а-я]*)', caseSensitive: false),
              (m) => '**${m[0]}**')
          .replaceAllMapped(
              RegExp(r'(уступ[а-я]* дорогу)', caseSensitive: false),
              (m) => '**${m[0]}**')
          .replaceAllMapped(
              RegExp(r'(запрещен[а-я]*)', caseSensitive: false),
              (m) => '**${m[0]}**')
          .replaceAllMapped(
              RegExp(r'(разрешен[а-я]*)', caseSensitive: false),
              (m) => '**${m[0]}**');

      cleaned = cleaned.replaceAll('****', '**');
      buffer.writeln(cleaned);
    } else {
      buffer.writeln(
          'Руководствуйтесь требованиями **дорожных знаков**, **разметки** и приоритета движения.');
    }

    buffer.writeln();
    buffer.writeln('⚡ **Как легко запомнить:**');
    buffer.writeln(_generateMnemonic(
        questionText, correctAnswerText, officialExplanation));

    return buffer.toString();
  }

  /// Умная мнемоника и подсказка под конкретную тему вопроса
  String _generateMnemonic(String questionText, String correctAnswerText,
      String? officialExplanation) {
    final q = questionText.toLowerCase();
    final exp = (officialExplanation ?? '').toLowerCase();
    final combined = '$q $exp';

    if (combined.contains('светофор') || combined.contains('сигнал')) {
      return 'Зеленый сигнал **отменяет знаки приоритета**, но при повороте налево всегда уступаем встречным прямо и направо.';
    } else if (combined.contains('регулировщик') || combined.contains('жезл')) {
      return 'Сигналы регулировщика **главнее всех**: и светофоров, и знаков приоритета, и разметки!';
    } else if (combined.contains('перекрест') ||
        combined.contains('поворот') ||
        combined.contains('уступ')) {
      return 'На равнозначном перекрестке — действует **помеха справа**. На неравнозначном — приоритет у тех, кто на **главной дороге**.';
    } else if (combined.contains('обгон') ||
        combined.contains('опережен') ||
        combined.contains('встречн')) {
      return 'Обгон на нерегулируемом перекрестке разрешен **только по главной дороге**. На мостах, переходах и Ж/Д переездах обгон **запрещен**!';
    } else if (combined.contains('остановк') ||
        combined.contains('стоянк') ||
        combined.contains('парковк')) {
      return 'До пешеходного перехода и перекрестка — **не менее 5 метров**, до остановки автобуса/трамвая — **15 метров**!';
    } else if (combined.contains('знак') || combined.contains('разметк')) {
      return 'Дорожные знаки **всегда имеют приоритет** перед дорожной разметкой (особенно временные знаки на желтом фоне).';
    } else if (combined.contains('скорост') || combined.contains('км/ч')) {
      return 'Базовые лимиты: жилая зона — **20 км/ч**, город — **60 км/ч**, трасса — **90 км/ч**, автомагистраль — **110 км/ч**.';
    } else if (combined.contains('пешеход') || combined.contains('переход')) {
      return 'Если пешеход вступил на проезжую часть — водитель **обязан уступить дорогу**.';
    } else if (combined.contains('круг') || combined.contains('кольц')) {
      return 'На круговом перекрестке въезжающий **уступает дорогу** тем, кто уже движется по кругу.';
    } else if (combined.contains('помощ') ||
        combined.contains('медицин') ||
        combined.contains('сердечн')) {
      return 'При первой помощи главное — **собственная безопасность**, затем остановка критических кровотечений и вызов 112.';
    } else if (combined.contains('неисправност') ||
        combined.contains('тормоз')) {
      return 'С неисправными тормозами, рулем, сцепным устройством или негорящими фарами ночью — **движение категорически запрещено**!';
    }

    return 'В любой спорной ситуации порядок разъезда определяют знаки приоритета, а при их отсутствии — **правило правой руки**.';
  }

  /// Умная генерация контекстных вопросов-подсказок для нижних табов
  List<String> getQuickSuggestionsForQuestion({
    required String questionText,
    required String? officialExplanation,
    required String correctAnswerText,
  }) {
    final q = questionText.toLowerCase();
    final exp = (officialExplanation ?? '').toLowerCase();
    final ans = correctAnswerText.toLowerCase();
    final combined = '$q $exp $ans';

    final List<String> suggestions = [];

    if (combined.contains('светофор') ||
        combined.contains('сигнал') ||
        combined.contains('стрелк')) {
      suggestions.add('🚦 А если светофор сломан или мигает желтый?');
      suggestions.add('🟢 В чем разница стрелки и основного зеленого?');
    } else if (combined.contains('регулировщик') ||
        combined.contains('жезл')) {
      suggestions.add('👮 Как легко запомнить жесты регулировщика?');
      suggestions.add('🚦 Что главнее: светофор или регулировщик?');
    } else if (combined.contains('перекрест') ||
        combined.contains('поворот') ||
        combined.contains('уступ')) {
      suggestions.add('🚗 Кто уступает при повороте налево?');
      suggestions.add('🛑 Как работает правило «помехи справа»?');
    } else if (combined.contains('обгон') ||
        combined.contains('опережен') ||
        combined.contains('встречн')) {
      suggestions.add('⛔ Где обгон категорически запрещен?');
      suggestions.add('🏎️ Чем обгон отличается от опережения?');
    } else if (combined.contains('остановк') ||
        combined.contains('стоянк') ||
        combined.contains('парковк')) {
      suggestions.add('🅿️ Сколько метров до перехода и остановки?');
      suggestions.add('⏱️ Чем остановка отличается от стоянки?');
    } else if (combined.contains('знак') ||
        combined.contains('табличк') ||
        combined.contains('разметк')) {
      suggestions.add('🛑 До какого места действует этот знак?');
      suggestions.add('🛣️ Что главнее: дорожный знак или разметка?');
    } else if (combined.contains('скорост') || combined.contains('км/ч')) {
      suggestions.add('⚡ Какая скорость в жилой зоне и на трассе?');
      suggestions.add('📸 С какого превышения приходит штраф?');
    } else if (combined.contains('пешеход') ||
        combined.contains('переход') ||
        combined.contains('зебр')) {
      suggestions.add('🚶 Когда водитель обязан уступить пешеходу?');
      suggestions.add('🛴 А если на переходе велосипедист?');
    } else if (combined.contains('круг') || combined.contains('кольц')) {
      suggestions.add('🔄 Кто главный на круговом перекрестке?');
      suggestions.add('➡️ С какой полосы разрешен съезд с круга?');
    } else if (combined.contains('помощ') ||
        combined.contains('медицин') ||
        combined.contains('кровотечен')) {
      suggestions.add('🩹 Какой порядок оказания первой помощи?');
      suggestions.add('🚨 Как правильно накладывать жгут?');
    } else if (combined.contains('неисправност') ||
        combined.contains('тормоз') ||
        combined.contains('рулев')) {
      suggestions.add('🔧 С какими поломками движение запрещено?');
      suggestions.add('⚠️ Можно ли своим ходом доехать до СТО?');
    } else if (combined.contains('штраф') ||
        combined.contains('лишен') ||
        combined.contains('коап')) {
      suggestions.add('⚖️ Какой штраф или статья за это нарушение?');
      suggestions.add('💳 Можно ли оплатить штраф со скидкой?');
    } else {
      suggestions.add('🚗 Кто имеет преимущество в этой ситуации?');
      suggestions.add('⚠️ В чем главная опасность для водителя?');
    }

    // Любимый пользователем таб в конце списка
    suggestions.add('💡 Как легко запомнить?');

    return suggestions;
  }

  String _generateContextualOfflineExplanation({
    required String questionText,
    required String correctAnswerText,
    required String? officialExplanation,
  }) {
    return buildInstantPrewrittenExplanation(
      questionText: questionText,
      correctAnswerText: correctAnswerText,
      officialExplanation: officialExplanation,
    );
  }

  String _generateContextualFollowup({
    required String userMessage,
    required String correctAnswerText,
    required String? officialExplanation,
  }) {
    final lower = userMessage.toLowerCase();
    final pddKeywords = [
      'пдд', 'правил', 'знак', 'дорог', 'светофор', 'разметк', 'перекрест',
      'поворот', 'разворот', 'обгон', 'опережен', 'уступ', 'машин', 'авто',
      'водитель', 'пешеход', 'штраф', 'коап', 'права', 'экзамен', 'гаи',
      'гибдд', 'билет', 'скорост', 'парковк', 'стоян', 'останов', 'помощ',
      'неисправн', 'почему', 'как', 'кто', 'где', 'запомн', 'траектор', 'лишен'
    ];
    final isRelevant =
        pddKeywords.any((k) => lower.contains(k)) || lower.length < 15;
    if (!isRelevant) {
      return 'Я персональный автоинструктор по ПДД и вождению 🚗 Могу ответить на любые вопросы по правилам дорожного движения, билетам, штрафам, экзаменам в ГИБДД или поведению на дороге. Пожалуйста, задайте вопрос по дорожной ситуации!';
    }

    return 'В данной ситуации важно помнить базовый принцип: «$correctAnswerText». '
        '${officialExplanation ?? 'Руководствуйтесь требованиями дорожных знаков, светофоров и правилом помехи справа.'} '
        'Если у вас есть дополнительные вопросы по траектории или знакам — напишите, разберем подробнее!';
  }

  Future<void> _cacheResult(String questionId, String text) async {
    _memoryCache[questionId] = text;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefKeyPrefix$questionId', text);
    } catch (_) {}
  }
}
