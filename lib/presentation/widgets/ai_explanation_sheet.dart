import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/services/gemini_ai_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/presentation/widgets/premium_paywall_sheet.dart';

class AiExplanationSheet extends StatefulWidget {
  final String questionId;
  final String questionText;
  final List<String> answers;
  final int correctAnswerIndex;
  final String? officialExplanation;

  const AiExplanationSheet({
    super.key,
    required this.questionId,
    required this.questionText,
    required this.answers,
    required this.correctAnswerIndex,
    this.officialExplanation,
  });

  static Future<void> show({
    required BuildContext context,
    required String questionId,
    required String questionText,
    required List<String> answers,
    required int correctAnswerIndex,
    String? officialExplanation,
  }) async {
    HapticFeedbackHelper.tap();
    if (!PremiumService.instance.canSendAiMessage) {
      await PremiumPaywallSheet.show(context);
      return;
    }

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiExplanationSheet(
        questionId: questionId,
        questionText: questionText,
        answers: answers,
        correctAnswerIndex: correctAnswerIndex,
        officialExplanation: officialExplanation,
      ),
    );
  }

  @override
  State<AiExplanationSheet> createState() => _AiExplanationSheetState();
}

class _AiExplanationSheetState extends State<AiExplanationSheet> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  String? _initialExplanation;
  bool _isLoadingInitial = false;
  String? _initialError;

  final List<AiChatMessage> _chatMessages = [];
  bool _isSendingMessage = false;

  List<String> _quickSuggestions = [];

  @override
  void initState() {
    super.initState();
    final correctAnswerText = (widget.correctAnswerIndex >= 0 &&
            widget.correctAnswerIndex < widget.answers.length)
        ? widget.answers[widget.correctAnswerIndex]
        : '';

    // Индивидуальные контекстные вопросы-подсказки под тему вопроса
    _quickSuggestions =
        GeminiAiService.instance.getQuickSuggestionsForQuestion(
      questionText: widget.questionText,
      officialExplanation: widget.officialExplanation,
      correctAnswerText: correctAnswerText,
    );

    _loadInitialExplanation();
  }

  void _loadInitialExplanation() {
    final correctAnswerText = (widget.correctAnswerIndex >= 0 &&
            widget.correctAnswerIndex < widget.answers.length)
        ? widget.answers[widget.correctAnswerIndex]
        : '';

    // Мгновенный готовый первичный разбор от ИИ без задержек и спиннеров
    setState(() {
      _initialExplanation =
          GeminiAiService.instance.buildInstantPrewrittenExplanation(
        questionText: widget.questionText,
        correctAnswerText: correctAnswerText,
        officialExplanation: widget.officialExplanation,
      );
      _isLoadingInitial = false;
      _initialError = null;
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSendMessage([String? predefinedText]) async {
    final textToSend = (predefinedText ?? _textController.text).trim();
    if (textToSend.isEmpty || _isSendingMessage) return;

    final isPremium = PremiumService.instance.isPremium;
    if (!isPremium && PremiumService.instance.remainingAiMessages <= 0) {
      await PremiumPaywallSheet.show(context);
      return;
    }

    HapticFeedbackHelper.tap();
    _textController.clear();

    // Списываем 1 бесплатный вопрос из общего лимита ИИ для аккаунта
    if (!isPremium) {
      await PremiumService.instance.recordAiMessageSent();
    }

    final userMessage = AiChatMessage(
      text: textToSend,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _chatMessages.add(userMessage);
      _isSendingMessage = true;
    });

    _scrollToBottom();

    try {
      final history = <AiChatMessage>[
        if (_initialExplanation != null)
          AiChatMessage(
            text: _initialExplanation!,
            isUser: false,
            timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
          ),
        ..._chatMessages,
      ];

      final reply = await GeminiAiService.instance.askAiQuestion(
        questionId: widget.questionId,
        questionText: widget.questionText,
        answers: widget.answers,
        correctAnswerIndex: widget.correctAnswerIndex,
        officialExplanation: widget.officialExplanation,
        conversationHistory: history,
        userMessage: textToSend,
      );

      if (mounted) {
        setState(() {
          _chatMessages.add(
            AiChatMessage(
              text: reply,
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
          _isSendingMessage = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _chatMessages.add(
            AiChatMessage(
              text:
                  'Не удалось получить ответ. Проверьте интернет-соединение и попробуйте еще раз.',
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
          _isSendingMessage = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return ListenableBuilder(
      listenable: PremiumService.instance,
      builder: (context, _) {
        final isPrem = PremiumService.instance.isPremium;
        final remaining = PremiumService.instance.remainingAiMessages;
        final limit = PremiumService.instance.aiFreeLimit;
        final hasReachedLimit = !isPrem && remaining <= 0;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Header with Title & Limit Badge
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppDimensions.screenPadding,
                      14,
                      AppDimensions.screenPadding,
                      10,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: colors.premiumAmberSurface,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 15,
                                color: colors.premiumAmber,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Разбор от ИИ',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: colors.premiumAmber,
                                  fontFamily: 'Onest',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isPrem)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF162B1D)
                                  : const Color(0xFFE8F8F0),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'PRO',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2BC280),
                                fontFamily: 'Onest',
                              ),
                            ),
                          )
                        else
                          GestureDetector(
                            onTap: () => PremiumPaywallSheet.show(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: remaining > 0
                                    ? (isDark
                                        ? const Color(0xFF2E2215)
                                        : const Color(0xFFFFF7ED))
                                    : (isDark
                                        ? const Color(0xFF341717)
                                        : const Color(0xFFFFECE8)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                remaining > 0
                                    ? '$remaining из $limit'
                                    : 'Лимит 0 из $limit',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: remaining > 0
                                      ? const Color(0xFFFFA53C)
                                      : const Color(0xFFED4621),
                                  fontFamily: 'Onest',
                                ),
                              ),
                            ),
                          ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.close_rounded,
                              color: colors.secondaryText, size: 22),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),

                  // 2. Chat Timeline
                  Expanded(
                    child: _isLoadingInitial
                        ? _buildLoadingInitial(colors)
                        : _initialError != null
                            ? _buildErrorInitial(colors)
                            : _buildChatList(colors),
                  ),

                  // 3. Quick Suggestion Chips (only when limit not reached)
                  if (!_isLoadingInitial && _initialError == null && !hasReachedLimit)
                    _buildQuickSuggestions(colors),

                  // 4. Input Field Bar OR Premium Limit Banner
                  if (!_isLoadingInitial && _initialError == null)
                    if (hasReachedLimit)
                      _buildLimitReachedBanner(colors, isDark)
                    else
                      _buildInputBar(colors),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

  Widget _buildLimitReachedBanner(AppThemeColors colors, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppDimensions.screenPadding,
        6,
        AppDimensions.screenPadding,
        14,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFA53C),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.hourglass_empty_rounded,
            color: Colors.white,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Лимит 10 вопросов исчерпан',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontFamily: 'Onest',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Оформите Premium для безлимитного ИИ',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: 0.95),
                    fontFamily: 'Onest',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: () => PremiumPaywallSheet.show(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF121212),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Premium',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF121212),
                fontFamily: 'Onest',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingInitial(AppThemeColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colors.premiumAmber,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'ИИ анализирует ситуацию на дороге...',
              style: TextStyle(
                fontSize: 14,
                color: colors.secondaryText,
                fontFamily: 'Onest',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorInitial(AppThemeColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Не удалось загрузить ответ',
              style: TextStyle(
                  color: colors.red, fontSize: 14, fontFamily: 'Onest'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadInitialExplanation,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.premiumAmber,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Повторить',
                  style: TextStyle(fontFamily: 'Onest')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatList(AppThemeColors colors) {
    return ListView(
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.screenPadding,
        8,
        AppDimensions.screenPadding,
        14,
      ),
      children: [
        // Initial AI Explanation Card (Плоский дизайн без обводки)
        if (_initialExplanation != null)
          _buildInitialExplanationCard(colors, _initialExplanation!),

        // Conversation history bubbles (Без обводок)
        ..._chatMessages.map((msg) => _buildMessageBubble(colors, msg)),

        // Typing indicator
        if (_isSendingMessage) _buildTypingIndicator(colors),
      ],
    );
  }

  Widget _buildInitialExplanationCard(AppThemeColors colors, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: _buildFormattedAiText(
        text,
        defaultColor: colors.primaryText,
        fontSize: 14,
        height: 1.55,
      ),
    );
  }

  Widget _buildMessageBubble(AppThemeColors colors, AiChatMessage msg) {
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colors.accent,
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          ),
          child: Text(
            msg.text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Colors.white,
              fontFamily: 'Onest',
            ),
          ),
        ),
      );
    } else {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, right: 30),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.smart_toy_outlined,
                      size: 13.5, color: colors.premiumAmber),
                  const SizedBox(width: 5),
                  Text(
                    'ИИ-Автоинструктор',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: colors.secondaryText,
                      fontFamily: 'Onest',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _buildFormattedAiText(
                msg.text,
                defaultColor: colors.primaryText,
                fontSize: 14,
                height: 1.48,
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildFormattedAiText(
    String rawText, {
    required Color defaultColor,
    double fontSize = 14,
    double height = 1.5,
    FontWeight defaultWeight = FontWeight.w400,
  }) {
    final cleaned = rawText
        .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    final spans = <InlineSpan>[];
    final regExp = RegExp(r'\*\*(.+?)\*\*');
    int lastMatchEnd = 0;

    for (final match in regExp.allMatches(cleaned)) {
      if (match.start > lastMatchEnd) {
        spans.add(
          TextSpan(
            text: cleaned.substring(lastMatchEnd, match.start),
            style: TextStyle(
              color: defaultColor,
              fontSize: fontSize,
              height: height,
              fontWeight: defaultWeight,
              fontFamily: 'Onest',
            ),
          ),
        );
      }
      final boldText = match.group(1) ?? '';
      spans.add(
        TextSpan(
          text: boldText,
          style: TextStyle(
            color: defaultColor,
            fontSize: fontSize,
            height: height,
            fontWeight: FontWeight.w700,
            fontFamily: 'Onest',
          ),
        ),
      );
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < cleaned.length) {
      spans.add(
        TextSpan(
          text: cleaned.substring(lastMatchEnd),
          style: TextStyle(
            color: defaultColor,
            fontSize: fontSize,
            height: height,
            fontWeight: defaultWeight,
            fontFamily: 'Onest',
          ),
        ),
      );
    }

    return Text.rich(
      TextSpan(children: spans),
      style: TextStyle(
        fontSize: fontSize,
        height: height,
        fontFamily: 'Onest',
      ),
    );
  }

  Widget _buildTypingIndicator(AppThemeColors colors) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.accent,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Нейросеть печатает ответ...',
              style: TextStyle(
                fontSize: 12.5,
                color: colors.secondaryText,
                fontFamily: 'Onest',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickSuggestions(AppThemeColors colors) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.screenPadding,
        vertical: 6,
      ),
      child: Row(
        children: _quickSuggestions.map((chipText) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              label: Text(
                chipText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.primaryText,
                  fontFamily: 'Onest',
                ),
              ),
              backgroundColor: colors.background,
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              onPressed: () => _handleSendMessage(chipText),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInputBar(AppThemeColors colors) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.screenPadding,
        6,
        AppDimensions.screenPadding,
        12,
      ),
      child: Container(
        height: 48,
        padding: const EdgeInsets.only(left: 16, right: 6),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSendMessage(),
                style: TextStyle(
                  fontSize: 14,
                  color: colors.primaryText,
                  fontFamily: 'Onest',
                ),
                decoration: InputDecoration(
                  hintText: 'Задайте вопрос нейросети...',
                  hintStyle: TextStyle(
                    fontSize: 13.5,
                    color: colors.secondaryText,
                    fontFamily: 'Onest',
                  ),
                  filled: false,
                  fillColor: Colors.transparent,
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isSendingMessage ? null : () => _handleSendMessage(),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: _isSendingMessage
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.arrow_upward_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
