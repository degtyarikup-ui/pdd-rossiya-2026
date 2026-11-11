import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/app_toast.dart';
import 'package:url_launcher/url_launcher.dart';

/// Элемент разобранного текста сообщения (обычный текст или кликабельная ссылка).
class LinkSpanInfo {
  const LinkSpanInfo({required this.text, this.url});

  final String text;
  final String? url;

  bool get isLink => url != null && url!.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkSpanInfo &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          url == other.url;

  @override
  int get hashCode => Object.hash(text, url);

  @override
  String toString() => isLink ? 'LINK("$text" -> $url)' : 'TEXT("$text")';
}

/// Удаляет markdown-разметку ссылок `[Текст](url)` -> `Текст` (для превью в баннерах и уведомлениях).
String stripMarkdownLinks(String text) {
  if (text.isEmpty) return text;
  return text.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\((?:[^\s()]|\([^\s()]*\))+\)'),
    (match) => match.group(1) ?? '',
  );
}

/// Приводит URL к валидной строке со схемой (по умолчанию https://).
String normalizeChatUrl(String rawUrl) {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) return '';
  if (RegExp(
    r'^[a-zA-Z][a-zA-Z0-9+.-]*:',
    caseSensitive: false,
  ).hasMatch(trimmed)) {
    return trimmed;
  }
  return 'https://$trimmed';
}

/// Разбивает текст на фрагменты обычного текста и кликабельных ссылок.
///
/// Распознаёт:
/// 1. Markdown-ссылки: `[Текст](url)`
/// 2. Прямые веб-ссылки: `https://...`, `http://...`
/// 3. Ссылки без схемы: `www....`, `t.me/...`
/// 4. Домены верхнего уровня: `.ru`, `.com`, `.org`, `.net`, `.online`, `.io`, `.me`, `.dev`, `.app`, `.edu`, `.gov`, `.рф`
/// 5. Email-адреса: `user@example.com` -> `mailto:user@example.com`
///
/// Знаки препинания на конце предложений (`.`, `,`, `;`, `:`, `!`, `?`, незакрытые скобки)
/// аккуратно отделяются от ссылки и остаются обычным текстом.
List<LinkSpanInfo> parseChatLinks(String text) {
  if (text.isEmpty) return const [];

  final regex = RegExp(
    r'''(\[(?<mdText>[^\]]+)\]\((?<mdUrl>(?:[^\s()]|\([^\s()]*\))+)\))|(?<email>[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})|(?<rawUrl>(?:https?:\/\/|www\.|t\.me\/|(?:[a-zA-Z0-9-]+\.)+(?:ru|com|org|net|online|io|me|dev|app|edu|gov|рф)(?:\/[^\s<>"'{}|\\^`\[\]]*)?)[^\s<>"'{}|\\^`\[\]]*)''',
    caseSensitive: false,
  );

  final result = <LinkSpanInfo>[];
  var lastIndex = 0;

  for (final match in regex.allMatches(text)) {
    if (match.start > lastIndex) {
      _addPlainText(result, text.substring(lastIndex, match.start));
    }

    final mdText = match.namedGroup('mdText');
    final mdUrl = match.namedGroup('mdUrl');
    final rawUrl = match.namedGroup('rawUrl');
    final email = match.namedGroup('email');

    if (mdText != null && mdUrl != null) {
      result.add(LinkSpanInfo(text: mdText, url: normalizeChatUrl(mdUrl)));
      lastIndex = match.end;
    } else if (rawUrl != null) {
      final cleaned = _trimTrailingPunctuation(rawUrl);
      if (cleaned.url.isEmpty) {
        _addPlainText(result, rawUrl);
      } else {
        result.add(
          LinkSpanInfo(text: cleaned.url, url: normalizeChatUrl(cleaned.url)),
        );
        if (cleaned.trailing.isNotEmpty) {
          _addPlainText(result, cleaned.trailing);
        }
      }
      lastIndex = match.end;
    } else if (email != null) {
      final cleaned = _trimTrailingPunctuation(email);
      if (cleaned.url.isEmpty) {
        _addPlainText(result, email);
      } else {
        result.add(
          LinkSpanInfo(text: cleaned.url, url: 'mailto:${cleaned.url}'),
        );
        if (cleaned.trailing.isNotEmpty) {
          _addPlainText(result, cleaned.trailing);
        }
      }
      lastIndex = match.end;
    }
  }

  if (lastIndex < text.length) {
    _addPlainText(result, text.substring(lastIndex));
  }

  return result;
}

void _addPlainText(List<LinkSpanInfo> list, String text) {
  if (text.isEmpty) return;
  if (list.isNotEmpty && !list.last.isLink) {
    list[list.length - 1] = LinkSpanInfo(text: list.last.text + text);
  } else {
    list.add(LinkSpanInfo(text: text));
  }
}

({String url, String trailing}) _trimTrailingPunctuation(String raw) {
  var url = raw;
  var trailing = '';

  while (url.isNotEmpty) {
    final lastChar = url[url.length - 1];
    if ('. , ; : ! ?'.split(' ').contains(lastChar)) {
      trailing = lastChar + trailing;
      url = url.substring(0, url.length - 1);
    } else if (lastChar == ')') {
      final openCount = '('.allMatches(url).length;
      final closeCount = ')'.allMatches(url).length;
      if (closeCount > openCount) {
        trailing = lastChar + trailing;
        url = url.substring(0, url.length - 1);
      } else {
        break;
      }
    } else {
      break;
    }
  }
  return (url: url, trailing: trailing);
}

/// Виджет текста сообщения чата техподдержки с интерактивными кликабельными ссылками.
class SupportChatMessageText extends StatefulWidget {
  const SupportChatMessageText({
    super.key,
    required this.text,
    required this.isUser,
    this.style,
    this.linkStyle,
    this.textAlign,
    this.onTapUrl,
  });

  final String text;
  final bool isUser;
  final TextStyle? style;
  final TextStyle? linkStyle;
  final TextAlign? textAlign;
  final FutureOr<void> Function(String url)? onTapUrl;

  @override
  State<SupportChatMessageText> createState() => _SupportChatMessageTextState();
}

class _SupportChatMessageTextState extends State<SupportChatMessageText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _handleLinkTap(String url) async {
    if (widget.onTapUrl != null) {
      await widget.onTapUrl!(url);
      return;
    }

    HapticFeedbackHelper.tap();
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (mounted) {
        AppToast.show(
          context,
          appL10n.linkOpenFailed,
          type: AppToastType.error,
        );
      }
      return;
    }

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        AppToast.show(
          context,
          appL10n.linkOpenFailed,
          type: AppToastType.error,
        );
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          appL10n.linkOpenFailed,
          type: AppToastType.error,
        );
      }
    }
  }

  List<InlineSpan> _buildSpans(TextStyle baseStyle, TextStyle linkStyle) {
    _clearRecognizers();
    final parts = parseChatLinks(widget.text);
    if (parts.isEmpty) return const [];

    final spans = <InlineSpan>[];
    for (final part in parts) {
      if (part.isLink && part.url != null) {
        final targetUrl = part.url!;
        final recognizer = TapGestureRecognizer()
          ..onTap = () => _handleLinkTap(targetUrl);
        _recognizers.add(recognizer);

        spans.add(
          TextSpan(
            text: part.text,
            style: linkStyle,
            recognizer: recognizer,
            mouseCursor: SystemMouseCursors.click,
          ),
        );
      } else {
        spans.add(TextSpan(text: part.text, style: baseStyle));
      }
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isUser = widget.isUser;

    final baseStyle =
        widget.style ??
        TextStyle(
          fontSize: 14.5,
          color: isUser ? Colors.white : colors.primaryText,
          height: 1.35,
        );

    final effectiveLinkStyle =
        widget.linkStyle ??
        TextStyle(
          fontSize: baseStyle.fontSize,
          height: baseStyle.height,
          color: isUser ? Colors.white : colors.accent,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationColor: isUser ? Colors.white : colors.accent,
        );

    final spans = _buildSpans(baseStyle, effectiveLinkStyle);
    if (spans.isEmpty) {
      return const SizedBox.shrink();
    }

    return Text.rich(
      TextSpan(style: baseStyle, children: spans),
      textAlign: widget.textAlign ?? TextAlign.start,
    );
  }
}
