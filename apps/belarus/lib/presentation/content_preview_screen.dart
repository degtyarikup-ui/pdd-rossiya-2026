import 'package:flutter/material.dart';
import '../domain/question_bank.dart';
import '../l10n/gen/app_localizations.dart';

/// Local source review, deliberately separate from the examination engine.
class ContentPreviewScreen extends StatefulWidget {
  final List<Question> questions;
  const ContentPreviewScreen({super.key, required this.questions});

  @override
  State<ContentPreviewScreen> createState() => _ContentPreviewScreenState();
}

class _ContentPreviewScreenState extends State<ContentPreviewScreen> {
  int _index = 0;
  bool _revealed = false;

  void _move(int delta) => setState(() {
    _index += delta;
    _revealed = false;
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final q = widget.questions[_index];
    return Scaffold(
      appBar: AppBar(title: Text(l.previewOpen)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              key: ValueKey(q.id),
              padding: const EdgeInsets.all(24),
              children: [
                Text(l.previewNotice),
                const SizedBox(height: 16),
                Text(l.previewPosition(_index + 1, widget.questions.length)),
                const SizedBox(height: 12),
                Text(q.text, style: Theme.of(context).textTheme.headlineSmall),
                for (final path in q.imageAssets)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Image.asset(
                      path,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Text(l.previewImageError),
                    ),
                  ),
                for (var i = 0; i < q.answers.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Text('${i + 1}.'),
                    title: Text(q.answers[i]),
                    trailing: _revealed && i == q.correctIndex
                        ? const Icon(Icons.check_circle)
                        : null,
                  ),
                if (!_revealed)
                  OutlinedButton(
                    onPressed: () => setState(() => _revealed = true),
                    child: Text(l.previewReveal),
                  ),
                if (_revealed) ...[
                  Text(l.correctAnswer(q.answers[q.correctIndex])),
                  Text(q.explanation),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  children: [
                    TextButton(
                      onPressed: _index > 0 ? () => _move(-1) : null,
                      child: Text(l.previewPrevious),
                    ),
                    TextButton(
                      onPressed: _index + 1 < widget.questions.length
                          ? () => _move(1)
                          : null,
                      child: Text(l.previewNext),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
