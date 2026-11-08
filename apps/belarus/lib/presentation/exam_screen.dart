import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/question_bank.dart';
import '../domain/exam_session.dart';
import '../l10n/gen/app_localizations.dart';

class ExamScreen extends StatefulWidget {
  final List<Question> questions;
  const ExamScreen({super.key, required this.questions});
  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> with WidgetsBindingObserver {
  late final ExamSession _session = ExamSession(
    widget.questions,
    startedAt: DateTime.now(),
  );
  late final Timer _timer;
  int _index = 0;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (mounted) setState(() => _session.tick(DateTime.now()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _tick();
  }

  @override
  void dispose() {
    _timer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.leaveTitle),
        content: Text(l.leaveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.stay),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.leave),
          ),
        ],
      ),
    );
    _leaving = false;
    if (!mounted) return;
    if (confirmed == true) {
      setState(_session.abandon);
      // Let PopScope observe the terminal state before popping.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final done = _session.outcome != null;
    final remaining = _session.remaining(DateTime.now());
    final time =
        '${remaining.inSeconds ~/ 60}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}';
    final q = widget.questions[_index];
    return PopScope(
      canPop: done,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(done ? l.result : l.exam),
          actions: [
            if (!done)
              Padding(padding: const EdgeInsets.all(16), child: Text(time)),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: done
                  ? ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Text(
                          _session.outcome == ExamOutcome.passed
                              ? l.passed
                              : _session.outcome == ExamOutcome.expired
                              ? l.expired
                              : l.failed,
                          style: Theme.of(context).textTheme.displayLarge,
                        ),
                        const SizedBox(height: 12),
                        Text(l.score(_session.correctCount)),
                        const SizedBox(height: 16),
                        for (final question in widget.questions)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(question.text),
                                  const SizedBox(height: 8),
                                  Text(
                                    l.correctAnswer(
                                      question.answers[question.correctIndex],
                                    ),
                                  ),
                                  Text(question.explanation),
                                ],
                              ),
                            ),
                          ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(l.home),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Text(
                          l.questionNumber(_index + 1),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          q.text,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 24),
                        for (var i = 0; i < q.answers.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: OutlinedButton(
                              onPressed: _session.answers.containsKey(q.id)
                                  ? null
                                  : () => setState(() {
                                      if (_session.submit(
                                            q.id,
                                            i,
                                            DateTime.now(),
                                          ) &&
                                          _session.outcome == null) {
                                        _index = widget.questions.indexWhere(
                                          (q) => !_session.answers.containsKey(
                                            q.id,
                                          ),
                                        );
                                      }
                                    }),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(q.answers[i]),
                              ),
                            ),
                          ),
                        Wrap(
                          spacing: 8,
                          children: List.generate(
                            10,
                            (index) => ChoiceChip(
                              label: Text('${index + 1}'),
                              selected: index == _index,
                              avatar:
                                  _session.answers.containsKey(
                                    widget.questions[index].id,
                                  )
                                  ? const Icon(Icons.check, size: 16)
                                  : null,
                              onSelected: (_) => setState(() => _index = index),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
