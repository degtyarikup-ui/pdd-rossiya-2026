import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/install_reporter.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/data/services/network_retry.dart';
import 'package:pdd_app/l10n/l10n.dart';

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

  static const String _prefKeyPrefix = 'ai_explanation_v2_';
  final Map<String, String> _memoryCache = {};

  /// The worker reads at most 64 KiB before validating recent chat turns.
  /// Bound the outgoing copy, keeping the complete conversation in the UI.
  Map<String, dynamic> _requestPayload({
    required String questionId,
    required String questionText,
    required List<String> answers,
    required int correctAnswerIndex,
    required String? officialExplanation,
    List<AiChatMessage> messages = const [],
    String? userMessage,
  }) {
    String clip(String value, int limit) =>
        value.length <= limit ? value : value.substring(0, limit);
    final recent = messages
        .skip(messages.length > 20 ? messages.length - 20 : 0)
        .map(
          (message) => {
            'text': clip(message.text, 2000),
            'isUser': message.isUser,
          },
        )
        .toList();
    final boundedAnswers = answers.take(6).map((a) => clip(a, 1000)).toList();
    final payload = <String, dynamic>{
      'questionId': clip(questionId, 128),
      'questionText': clip(questionText, 1000),
      'answers': boundedAnswers,
      'correctAnswerIndex': correctAnswerIndex,
      'officialExplanation': clip(officialExplanation ?? '', 8000),
      if (messages.isNotEmpty) 'messages': recent,
      if (userMessage != null) 'userMessage': clip(userMessage, 4000),
    };
    // Character limits alone are insufficient: Cyrillic, emoji and JSON escape
    // sequences can require several bytes per character.
    while (utf8.encode(jsonEncode(payload)).length > 65000) {
      if (recent.isNotEmpty) {
        recent.removeAt(0);
        continue;
      }
      final explanation = payload['officialExplanation'] as String;
      if (explanation.isNotEmpty) {
        payload['officialExplanation'] = clip(
          explanation,
          explanation.length ~/ 2,
        );
        continue;
      }
      var longestAnswer = -1;
      for (var i = 0; i < boundedAnswers.length; i++) {
        if (boundedAnswers[i].isNotEmpty &&
            (longestAnswer < 0 ||
                boundedAnswers[i].length >
                    boundedAnswers[longestAnswer].length)) {
          longestAnswer = i;
        }
      }
      if (longestAnswer >= 0) {
        final answer = boundedAnswers[longestAnswer];
        boundedAnswers[longestAnswer] = clip(answer, answer.length ~/ 2);
      } else {
        // Only pathological escaped text can reach this fallback: real
        // question/answer payloads fit the worker's limits without changes.
        final question = payload['questionText'] as String;
        if (question.isNotEmpty) {
          payload['questionText'] = clip(question, question.length ~/ 2);
        } else {
          final message = payload['userMessage'] as String? ?? '';
          payload['userMessage'] = clip(message, message.length ~/ 2);
        }
      }
    }
    return payload;
  }

  String _cacheKey(
    String id,
    String text,
    List<String> answers,
    int correct,
    String? comment,
  ) => sha256
      .convert(
        utf8.encode(
          jsonEncode([id, text, answers, correct, comment, appL10n.localeName]),
        ),
      )
      .toString();

  Future<Map<String, dynamic>> _send(Map<String, dynamic> payload) async {
    final revision = AuthService.instance.accountRevision;
    final installation = await InstallReporter.installationId();
    payload['installationId'] = installation.length > 128
        ? installation.substring(0, 128)
        : installation;
    payload['locale'] = appL10n.localeName;
    // AI quota accounting is a side effect: never retry an unknown POST result.
    final host =
        BackendConfig.notifierHosts[NotifierRoute.preferredIndex(
          BackendConfig.notifierHosts,
        )];
    final response = await http
        .post(
          Uri.parse('$host/api/ai/chat'),
          headers: AuthService.instance.serverHeaders,
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 12));
    final data = jsonDecode(response.body);
    if (revision != AuthService.instance.accountRevision) {
      throw const AiServiceException(authenticationRequired: true);
    }
    if (data is! Map<String, dynamic>) {
      throw const FormatException('invalid AI response');
    }
    PremiumService.instance.applyAiQuota(data);
    if (response.statusCode == 401) {
      throw const AiServiceException(authenticationRequired: true);
    }
    if (response.statusCode == 429) {
      throw AiServiceException(
        quotaExceeded: data['remaining'] == 0,
        retryAfterSeconds: data['retryAfterSeconds'] is num
            ? (data['retryAfterSeconds'] as num).toInt().clamp(1, 86400)
            : 60,
      );
    }
    if (response.statusCode != 200 ||
        data['generated'] == false ||
        data['reply'] is! String ||
        (data['reply'] as String).trim().isEmpty) {
      throw const AiServiceException();
    }
    return data;
  }

  Future<void> refreshQuota() async {
    final revision = AuthService.instance.accountRevision;
    try {
      final installation = await InstallReporter.installationId();
      final response = await sendWithRetry(
        (host) => http.get(
          Uri.parse(
            '$host/api/ai/status',
          ).replace(queryParameters: {'installationId': installation}),
          headers: AuthService.instance.serverHeaders,
        ),
        hosts: BackendConfig.notifierHosts,
      );
      if (response.statusCode == 200 &&
          revision == AuthService.instance.accountRevision) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          PremiumService.instance.applyAiQuota(data);
        }
      }
    } catch (_) {
      /* An unavailable quota endpoint never hides official content. */
    }
  }

  Future<String> explainQuestion({
    required String questionId,
    required String questionText,
    required List<String> answers,
    required int correctAnswerIndex,
    required String? officialExplanation,
  }) async {
    final key = _cacheKey(
      questionId,
      questionText,
      answers,
      correctAnswerIndex,
      officialExplanation,
    );
    if (_memoryCache.containsKey(key)) return _memoryCache[key]!;
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('$_prefKeyPrefix$key');
    if (cached != null) return _memoryCache[key] = cached;
    try {
      final data = await _send(
        _requestPayload(
          questionId: questionId,
          questionText: questionText,
          answers: answers,
          correctAnswerIndex: correctAnswerIndex,
          officialExplanation: officialExplanation,
        ),
      );
      final reply = (data['reply'] as String).trim();
      _memoryCache[key] = reply;
      await prefs.setString('$_prefKeyPrefix$key', reply);
      return reply;
    } catch (_) {
      // A local comment is never cached as a generated model explanation.
      return buildInstantPrewrittenExplanation(
        questionText: questionText,
        correctAnswerText:
            correctAnswerIndex >= 0 && correctAnswerIndex < answers.length
            ? answers[correctAnswerIndex]
            : '',
        officialExplanation: officialExplanation,
      );
    }
  }

  Future<String> askAiQuestion({
    required String questionId,
    required String questionText,
    required List<String> answers,
    required int correctAnswerIndex,
    required String? officialExplanation,
    required List<AiChatMessage> conversationHistory,
    required String userMessage,
  }) async {
    final data = await _send(
      _requestPayload(
        questionId: questionId,
        questionText: questionText,
        answers: answers,
        correctAnswerIndex: correctAnswerIndex,
        officialExplanation: officialExplanation,
        messages: conversationHistory,
        userMessage: userMessage,
      ),
    );
    return (data['reply'] as String).trim();
  }

  /// Only the source comment and correct answer are shown locally. Keyword
  /// heuristics cannot safely infer priority rules or a regulator's signal.
  String buildInstantPrewrittenExplanation({
    required String questionText,
    required String correctAnswerText,
    required String? officialExplanation,
  }) {
    return '${appL10n.aiCorrectAnswer(correctAnswerText)}\n\n'
        '**${appL10n.aiOfficialComment}**\n${officialExplanation?.trim().isNotEmpty == true ? officialExplanation!.trim() : appL10n.aiNoOfficialComment}';
  }

  List<String> getQuickSuggestionsForQuestion({
    required String questionText,
    required String? officialExplanation,
    required String correctAnswerText,
  }) => [
    appL10n.aiSuggestRule,
    appL10n.aiSuggestWhy,
    appL10n.aiSuggestExceptions,
  ];
}

class AiServiceException implements Exception {
  const AiServiceException({
    this.authenticationRequired = false,
    this.quotaExceeded = false,
    this.retryAfterSeconds = 0,
  });
  final bool authenticationRequired;
  final bool quotaExceeded;
  final int retryAfterSeconds;
}
