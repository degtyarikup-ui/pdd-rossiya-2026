import 'package:pdd_app/core/config/backend_config.dart';

enum SupportMessageSender { user, support }

enum SupportMessageStatus { sending, sent, failed }

/// Модель сообщения в чате техподдержки.
class SupportChatMessage {
  final String id;
  final String text;
  final String? imageUrl;
  final String? localImagePath;
  final SupportMessageSender sender;
  final int timestamp;
  final String? authorName;
  final SupportMessageStatus status;

  const SupportChatMessage({
    required this.id,
    required this.text,
    this.imageUrl,
    this.localImagePath,
    required this.sender,
    required this.timestamp,
    this.authorName,
    this.status = SupportMessageStatus.sent,
  });

  bool get isUser => sender == SupportMessageSender.user;
  bool get isSupport => sender == SupportMessageSender.support;
  bool get hasImage =>
      (imageUrl != null && imageUrl!.isNotEmpty) ||
      (localImagePath != null && localImagePath!.isNotEmpty);

  /// Полный URL изображения (если передан относительный путь от воркера).
  String? get fullImageUrl {
    if (imageUrl == null || imageUrl!.isEmpty) return null;
    if (imageUrl!.startsWith('http://') || imageUrl!.startsWith('https://')) {
      return imageUrl;
    }
    final base = BackendConfig.notifierUrl.replaceAll(RegExp(r'/+$'), '');
    final path = imageUrl!.startsWith('/') ? imageUrl! : '/$imageUrl';
    return '$base$path';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    if (imageUrl != null) 'imageUrl': imageUrl,
    if (localImagePath != null) 'localImagePath': localImagePath,
    'sender': sender == SupportMessageSender.user ? 'user' : 'support',
    'ts': timestamp,
    if (authorName != null) 'authorName': authorName,
    'status': status.name,
  };

  factory SupportChatMessage.fromJson(Map<String, dynamic> json) {
    return SupportChatMessage(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      localImagePath: json['localImagePath'] as String?,
      sender: json['sender'] == 'support'
          ? SupportMessageSender.support
          : SupportMessageSender.user,
      timestamp: (json['ts'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      authorName: json['authorName'] as String?,
      status: SupportMessageStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => SupportMessageStatus.sent,
      ),
    );
  }

  SupportChatMessage copyWith({
    String? id,
    String? text,
    String? imageUrl,
    String? localImagePath,
    SupportMessageSender? sender,
    int? timestamp,
    String? authorName,
    SupportMessageStatus? status,
  }) {
    return SupportChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      imageUrl: imageUrl ?? this.imageUrl,
      localImagePath: localImagePath ?? this.localImagePath,
      sender: sender ?? this.sender,
      timestamp: timestamp ?? this.timestamp,
      authorName: authorName ?? this.authorName,
      status: status ?? this.status,
    );
  }
}
