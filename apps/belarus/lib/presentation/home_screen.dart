import 'package:flutter/material.dart';
import '../domain/question_bank.dart';
import '../l10n/gen/app_localizations.dart';
import 'exam_screen.dart';

class HomeScreen extends StatefulWidget {
  final Future<QuestionBank> Function() loader;
  const HomeScreen({super.key, required this.loader});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<QuestionBank> _bank = widget.loader();
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l.appTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: FutureBuilder<QuestionBank>(
              future: _bank,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l.loadError),
                      TextButton(
                        onPressed: () => setState(() {
                          _bank = widget.loader();
                        }),
                        child: Text(l.retry),
                      ),
                    ],
                  );
                }
                if (!snapshot.hasData) return const CircularProgressIndicator();
                final bank = snapshot.requireData;
                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      l.welcome,
                      style: Theme.of(context).textTheme.displayLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(l.intro),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Icon(Icons.fact_check_outlined, size: 48),
                            const SizedBox(height: 16),
                            Text(
                              l.exam,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              bank.canStartExam
                                  ? l.examRules
                                  : l.contentPending,
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: bank.canStartExam
                                  ? () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => ExamScreen(
                                          questions: bank.newExam(),
                                        ),
                                      ),
                                    )
                                  : null,
                              child: Text(
                                bank.canStartExam ? l.startExam : l.preparing,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l.practiceNotice,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
