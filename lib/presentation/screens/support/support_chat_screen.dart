import 'package:pdd_app/core/layout/app_content_frame.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/support_chat_message.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/data/services/support_chat_service.dart';
import 'package:pdd_app/data/services/support_inbox.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
import 'package:pdd_app/presentation/widgets/app_loading_indicator.dart';
import 'package:pdd_app/presentation/widgets/support_chat_image.dart';

/// Экран интерактивного чата техподдержки приложения.
class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key, this.service});

  final SupportChatService? service;

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
  bool _isRefreshing = false;
  Timer? _pollTimer;

  SupportChatService get _service =>
      widget.service ?? SupportChatService.instance;

  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  final Map<String, Uint8List> _pendingBytesMap = {};

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
    final cached = await _service.loadCachedMessages();
    if (!mounted) return;
    if (mounted) {
      setState(() {
        _messages = cached;
        _isLoading = false;
      });
      _scrollToBottom();
    }

    // 2. Сразу запрашиваем актуальные сообщения с сервера
    await _refreshMessages();
    if (!mounted) return;

    // 3. Пока чат открыт, спрашиваем раз в 3.5 секунды. Обращение закрыто
    // (/close) — оператор не напишет, пока не напишет человек: раз в 30 секунд.
    _pollTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      if (!mounted) return;
      final closed = _messages.isNotEmpty && _messages.last.isClosedNotice;
      if (closed &&
          DateTime.now().difference(_lastRefresh) <
              const Duration(seconds: 30)) {
        return;
      }
      _refreshMessages(silent: true);
    });
  }

  DateTime _lastRefresh = DateTime.now();

  Future<void> _refreshMessages({bool silent = false}) async {
    // Фото может грузиться дольше интервала polling. Не запускаем повторную
    // загрузку и не даём следующему ответу обогнать сообщение с фото.
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      await _fetchAndPrepareMessages(silent: silent);
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _fetchAndPrepareMessages({required bool silent}) async {
    _lastRefresh = DateTime.now();
    final lastTs = _messages.isNotEmpty
        ? _messages
              .where((m) => m.status == SupportMessageStatus.sent)
              .fold<int>(0, (max, m) => m.timestamp > max ? m.timestamp : max)
        : 0;

    final incoming = await _service.fetchMessages(
      since: lastTs > 0 ? lastTs : null,
    );

    if (!mounted || incoming.isEmpty) return;

    final displayedIds = _messages.map((m) => m.id).toSet();
    final images = incoming
        .where((m) => !displayedIds.contains(m.id))
        .map(_resolveImageProvider)
        .whereType<ImageProvider>()
        .toSet();
    // Публикуем новое сообщение с уже декодированным фото. Если сеть
    // медленная, через 8 с показываем карточку с индикатором, а не скрываем
    // ответ бесконечно. SupportChatImage использует тот же ImageCache.
    await Future.wait<void>(
      images.map((image) => precacheImage(image, context, onError: (_, _) {})),
    ).timeout(const Duration(seconds: 8), onTimeout: () => []);
    if (!mounted) return;

    // Shown here, so the banner over the app must not bring them up again.
    unawaited(SupportInbox.instance.markShown(incoming));

    final existingIds = _messages.map((m) => m.id).toSet();
    final newItems = incoming
        .where((m) => !existingIds.contains(m.id))
        .toList();

    if (newItems.isNotEmpty) {
      setState(() {
        _messages.addAll(newItems);
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      });
      await _service.saveCachedMessages(_messages);
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

  Future<void> _showImageSourcePicker() async {
    HapticFeedbackHelper.tap();
    final colors = AppColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.camera_alt_rounded,
                    color: colors.accent,
                    size: 22,
                  ),
                ),
                title: Text(
                  appL10n.supportChatCamera,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.photo_library_rounded,
                    color: colors.accent,
                    size: 22,
                  ),
                ),
                title: Text(
                  appL10n.supportChatGallery,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (bytes.lengthInBytes > 10 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(appL10n.supportChatImageTooLarge)),
          );
        }
        return;
      }
      setState(() {
        _selectedImage = picked;
        _selectedImageBytes = bytes;
      });
    } catch (_) {}
  }

  ImageProvider? _resolveImageProvider(SupportChatMessage msg) {
    if (_pendingBytesMap.containsKey(msg.id)) {
      return MemoryImage(_pendingBytesMap[msg.id]!);
    }
    if (!kIsWeb &&
        msg.localImagePath != null &&
        File(msg.localImagePath!).existsSync()) {
      return FileImage(File(msg.localImagePath!));
    }
    if (msg.fullImageUrl != null) {
      return NetworkImage(msg.fullImageUrl!);
    }
    return null;
  }

  void _openImageViewer(BuildContext context, ImageProvider imageProvider) {
    HapticFeedbackHelper.tap();
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image(image: imageProvider),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSend() async {
    final text = _textController.text.trim();
    final image = _selectedImage;
    final imageBytes = _selectedImageBytes;
    if ((text.isEmpty && imageBytes == null) || _isSending) return;

    HapticFeedbackHelper.tap();
    _textController.clear();
    setState(() {
      _isSending = true;
      _selectedImage = null;
      _selectedImageBytes = null;
    });

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    if (imageBytes != null) {
      _pendingBytesMap[tempId] = imageBytes;
    }

    final pendingMsg = SupportChatMessage(
      id: tempId,
      text: text,
      localImagePath: kIsWeb ? null : image?.path,
      sender: SupportMessageSender.user,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: SupportMessageStatus.sending,
    );

    setState(() {
      _messages.add(pendingMsg);
    });
    _scrollToBottom();

    final result = await _service.sendMessage(
      text,
      imageBytes: imageBytes,
      imageMimeType: image?.mimeType ?? 'image/jpeg',
      localImagePath: image?.path,
    );

    if (!mounted) return;

    setState(() {
      _isSending = false;
      final index = _messages.indexWhere((m) => m.id == tempId);
      if (index != -1) {
        if (result != null) {
          if (imageBytes != null) {
            _pendingBytesMap[result.id] = imageBytes;
            _pendingBytesMap.remove(tempId);
          }
          _messages[index] = result;
        } else {
          _messages[index] = pendingMsg.copyWith(
            status: SupportMessageStatus.failed,
          );
        }
      }
    });

    await _service.saveCachedMessages(_messages);
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

    Uint8List? retryBytes = _pendingBytesMap[failedMsg.id];
    if (retryBytes == null && failedMsg.localImagePath != null && !kIsWeb) {
      try {
        final f = File(failedMsg.localImagePath!);
        if (f.existsSync()) {
          retryBytes = await f.readAsBytes();
        }
      } catch (_) {}
    }

    final result = await _service.sendMessage(
      failedMsg.text,
      imageBytes: retryBytes,
      localImagePath: failedMsg.localImagePath,
    );
    if (!mounted) return;

    setState(() {
      final index = _messages.indexWhere((m) => m.id == failedMsg.id);
      if (index != -1) {
        if (result != null) {
          if (retryBytes != null) {
            _pendingBytesMap[result.id] = retryBytes;
            _pendingBytesMap.remove(failedMsg.id);
          }
          _messages[index] = result;
        } else {
          _messages[index] = failedMsg.copyWith(
            status: SupportMessageStatus.failed,
          );
        }
      }
    });

    await _service.saveCachedMessages(_messages);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return AppContentFrame(
      maxWidth: AppContentFrame.readingWidth,
      child: Scaffold(
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
                    ? const Center(child: AppLoadingIndicator())
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
                            return _buildMessageItem(_messages[index], colors);
                          },
                        ),
                      ),
              ),
              _buildInputArea(colors),
            ],
          ),
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

  /// Служебная плашка по центру (обращение завершено): не сообщение менеджера.
  Widget _buildSystemNotice(SupportChatMessage msg, AppThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppDimensions.spacingS,
        horizontal: AppDimensions.spacingL,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: colors.divider.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            msg.displayText,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.secondaryText,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageItem(SupportChatMessage msg, AppThemeColors colors) {
    if (msg.isClosedNotice) return _buildSystemNotice(msg, colors);
    final isUser = msg.isUser;
    final timeStr = _formatTime(msg.timestamp);
    final imageProvider = _resolveImageProvider(msg);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimensions.spacingM),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
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
              padding: EdgeInsets.symmetric(
                horizontal: imageProvider != null ? 8 : AppDimensions.spacingM,
                vertical: imageProvider != null
                    ? 8
                    : AppDimensions.spacingS + 2,
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
                crossAxisAlignment: isUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!isUser) ...[
                    Padding(
                      padding: EdgeInsets.only(
                        left: imageProvider != null ? 4 : 0,
                        bottom: 4,
                      ),
                      child: Text(
                        appL10n.supportManagerName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: colors.accent,
                        ),
                      ),
                    ),
                  ],
                  if (imageProvider != null) ...[
                    SupportChatImage(
                      key: ValueKey(msg.id),
                      image: imageProvider,
                      onTap: () => _openImageViewer(context, imageProvider),
                    ),
                    if (msg.displayText.isNotEmpty) const SizedBox(height: 6),
                  ],
                  if (msg.displayText.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: imageProvider != null ? 4 : 0,
                      ),
                      child: Text(
                        msg.displayText,
                        style: TextStyle(
                          fontSize: 14.5,
                          color: isUser ? Colors.white : colors.primaryText,
                          height: 1.35,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: EdgeInsets.only(
                      right: imageProvider != null ? 4 : 0,
                    ),
                    child: Row(
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectedImageBytes != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: AppDimensions.spacingS),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.divider.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      _selectedImageBytes!,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          appL10n.supportChatPhoto,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.primaryText,
                          ),
                        ),
                        if (_selectedImage != null)
                          Text(
                            _selectedImage!.name,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.secondaryText,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedImage = null;
                        _selectedImageBytes = null;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colors.divider.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: _isSending ? null : _showImageSourcePicker,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.background,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.divider.withValues(alpha: 0.5),
                      width: 0.5,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.add_photo_alternate_rounded,
                      color: colors.accent,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppDimensions.spacingS),
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
                    style: TextStyle(fontSize: 14.5, color: colors.primaryText),
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
                  final canSend =
                      (value.text.trim().isNotEmpty ||
                          _selectedImageBytes != null) &&
                      !_isSending;
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
