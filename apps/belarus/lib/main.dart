import 'package:flutter/material.dart';
import 'data/load_bank.dart';
import 'domain/question_bank.dart';
import 'l10n/gen/app_localizations.dart';
import 'presentation/app_theme.dart';
import 'presentation/home_screen.dart';

void main() => runApp(const BelarusApp());

class BelarusApp extends StatelessWidget {
  final Future<QuestionBank> Function()? bankLoader;
  const BelarusApp({super.key, this.bankLoader});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    home: HomeScreen(loader: bankLoader ?? loadBank),
  );
}
