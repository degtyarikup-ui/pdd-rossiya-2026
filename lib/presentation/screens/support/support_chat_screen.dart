import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/support_chat_message.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/data/services/support_chat_service.dart';
import 'package:pdd_app/data/services/support_inbox.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';

/// Экран интерактивного чата техподдержки приложения.
class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<SupportChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // While the chat is on screen the inbox does not show a banner: this screen shows the reply.
    SupportInbox.instance.chatOpen = true;
    _initChat();
  }

  @override
  void dispose() {
    SupportInbox.instance.chatOpen = false;
    _pollTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _initChat() async {
    // 1. Мгновенно отображаем локально сохранённую историю
    final cached = await SupportChatService.instance.loadCachedMessages();
    if (mounted) {
      setState(() {
        _messages = cached;
        _isLoading = false;
      });
      _scrollToBottom();
    }

    // 2. Сразу запрашиваем актуальные сообщения с сервера
    await _refreshMessages();

    // 3. Запускаем периодический опрос раз в 3.5 секунды
    _pollTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      if (mounted) _refreshMessages(silent: true);
    });
  }

  Future<void> _refreshMessages({bool silent = false}) async {
    final lastTs = _messages.isNotEmpty
        ? _messages
            .where((m) => m.status == SupportMessageStatus.sent)
            .fold<int>(0, (max, m) => m.timestamp > max ? m.timestamp : max)
        : 0;

    final incoming = await SupportChatService.instance.fetchMessages(
      since: lastTs > 0 ? lastTs : null,
    );

    if (!mounted || incoming.isEmpty) return;

    final existingIds = _messages.map((m) => m.id).toSet();
    final newItems = incoming.where((m) => !existingIds.contains(m.id)).toList();

    if (newItems.isNotEmpty) {
      setState(() {
        _messages.addAll(newItems);
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      });
      await SupportChatService.instance.saveCachedMessages(_messages);
      _scrollToBottom();
      if (newItems.any((m) => m.isSupport)) {
        SoundEffectsService.instance.playMessage();
      }
      if (!silent) HapticFeedbackHelper.tap();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _handleSend() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    HapticFeedbackHelper.tap();
    _textController.clear();
    setState(() => _isSending = true);

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final pendingMsg = SupportChatMessage(
      id: tempId,
      text: text,
      sender: SupportMessageSender.user,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: SupportMessageStatus.sending,
    );

    setState(() {
      _messages.add(pendingMsg);
    });
    _scrollToBottom();

    final result = await SupportChatService.instance.sendMessage(text);

    if (!mounted) return;

    setState(() {
      _isSending = false;
      final index = _messages.indexWhere((m) => m.id == tempId);
      if (index != -1) {
        if (result != null) {
          _messages[index] = result;
        } else {
          _messages[index] = pendingMsg.copyWith(
            status: SupportMessageStatus.failed,
          );
        }
      }
    });

    await SupportChatService.instance.saveCachedMessages(_messages);
    _scrollToBottom();
  }

  Future<void> _handleRetry(SupportChatMessage failedMsg) async {
    HapticFeedbackHelper.tap();
    setState(() {
      final index = _messages.indexWhere((m) => m.id == failedMsg.id);
      if (index != -1) {
        _messages[index] = failedMsg.copyWith(
          status: SupportMessageStatus.sending,
        );
      }
    });

    final result = await SupportChatService.instance.sendMessage(failedMsg.text);
    if (!mounted) return;

    setState(() {
      final index = _messages.indexWhere((m) => m.id == failedMsg.id);
      if (index != -1) {
        if (result != null) {
          _messages[index] = result;
        } else {
          _messages[index] = failedMsg.copyWith(
            status: SupportMessageStatus.failed,
          );
        }
      }
    });

    await SupportChatService.instance.saveCachedMessages(_messages);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.spacingM,
              vertical: AppDimensions.spacingXS,
            ),
            decoration: BoxDecoration(
              color: colors.background,
              border: Border(
                bottom: BorderSide(
                  color: colors.divider.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                AppChromeIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () {
                    HapticFeedbackHelper.tap();
                    Navigator.of(context).pop();
                  },
                ),
                const SizedBox(width: AppDimensions.spacingM),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.support_agent_rounded,
                    color: colors.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppDimensions.spacingS),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appL10n.supportChatTitle,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colors.primaryText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        appL10n.supportChatSubtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.secondaryText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: colors.accent,
                        strokeWidth: 2.5,
                      ),
                    )
                  : _messages.isEmpty
                      ? _buildEmptyState(colors)
                      : RefreshIndicator(
                          color: colors.accent,
                          onRefresh: () => _refreshMessages(silent: false),
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDimensions.spacingM,
                              vertical: AppDimensions.spacingM,
                            ),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              return _buildMessageItem(
                                _messages[index],
                                colors,
                              );
                            },
                          ),
                        ),
            ),
            _buildInputArea(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppThemeColors colors) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimensions.spacingXL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                color: colors.accent,
                size: 36,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingL),
            Text(
              appL10n.supportChatEmptyTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colors.primaryText,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimensions.spacingS),
            Text(
              appL10n.supportChatEmptySubtitle,
              style: TextStyle(
                fontSize: 13.5,
                color: colors.secondaryText,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageItem(SupportChatMessage msg, AppThemeColors colors) {
    final isUser = msg.isUser;
    final timeStr = _formatTime(msg.timestamp);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimensions.spacingM),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 8, bottom: 4),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/support_manager.webp',
                  width: 28,
                  height: 28,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.76,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.spacingM,
                vertical: AppDimensions.spacingS + 2,
              ),
              decoration: BoxDecoration(
                color: isUser ? colors.accent : colors.cardBackground,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: isUser
                    ? null
                    : Border.all(
                        color: colors.divider.withValues(alpha: 0.5),
                        width: 0.5,
                      ),
              ),
              child: Column(
                crossAxisAlignment:
                    isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isUser) ...[
                    Text(
                      appL10n.supportManagerName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: colors.accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    msg.text,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: isUser ? Colors.white : colors.primaryText,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isUser
                              ? Colors.white.withValues(alpha: 0.7)
                              : colors.secondaryText,
                        ),
                      ),
                      if (isUser) ...[
                        const SizedBox(width: 4),
                        if (msg.status == SupportMessageStatus.sending)
                          SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          )
                        else if (msg.status == SupportMessageStatus.sent)
                          Icon(
                            Icons.done_all_rounded,
                            size: 13,
                            color: Colors.white.withValues(alpha: 0.8),
                          )
                        else if (msg.status == SupportMessageStatus.failed)
                          GestureDetector(
                            onTap: () => _handleRetry(msg),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  size: 13,
                                  color: Colors.redAccent,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  appL10n.supportChatRetry,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(AppThemeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingM,
        vertical: AppDimensions.spacingS,
      ),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        border: Border(
          top: BorderSide(
            color: colors.divider.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: colors.divider.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              ),
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(
                  fontSize: 14.5,
                  color: colors.primaryText,
                ),
                decoration: InputDecoration(
                  hintText: appL10n.supportChatPlaceholder,
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: colors.secondaryText,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          const SizedBox(width: AppDimensions.spacingS),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _textController,
            builder: (context, value, _) {
              final canSend = value.text.trim().isNotEmpty && !_isSending;
              return GestureDetector(
                onTap: canSend ? _handleSend : null,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: canSend
                        ? colors.accent
                        : colors.divider.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 19,
                          ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final hours = dt.hour.toString().padLeft(2, '0');
    final minutes = dt.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }
}
