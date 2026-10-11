enum SupportMessageSender { user, support }

enum SupportMessageStatus { sending, sent, failed }

/// Модель сообщения в чате техподдержки.
class SupportChatMessage {
  final String id;
  final String text;
  final SupportMessageSender sender;
  final int timestamp;
  final String? authorName;
  final SupportMessageStatus status;

  const SupportChatMessage({
    required this.id,
    required this.text,
    required this.sender,
    required this.timestamp,
    this.authorName,
    this.status = SupportMessageStatus.sent,
  });

  bool get isUser => sender == SupportMessageSender.user;
  bool get isSupport => sender == SupportMessageSender.support;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'sender': sender == SupportMessageSender.user ? 'user' : 'support',
    'ts': timestamp,
    if (authorName != null) 'authorName': authorName,
    'status': status.name,
  };

  factory SupportChatMessage.fromJson(Map<String, dynamic> json) {
    return SupportChatMessage(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
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
    SupportMessageSender? sender,
    int? timestamp,
    String? authorName,
    SupportMessageStatus? status,
  }) {
    return SupportChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      sender: sender ?? this.sender,
      timestamp: timestamp ?? this.timestamp,
      authorName: authorName ?? this.authorName,
      status: status ?? this.status,
    );
  }
}
