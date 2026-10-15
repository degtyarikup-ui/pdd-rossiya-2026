import 'package:flutter/material.dart';

import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/app_loading_indicator.dart';

/// Present a real first frame before opening preferences and restoring sessions.
/// The actual application is mounted only after its required services are ready.
class AppStartupGate extends StatefulWidget {
  const AppStartupGate({super.key, required this.initialize});

  final Future<Widget> Function() initialize;

  @override
  State<AppStartupGate> createState() => _AppStartupGateState();
}

class _AppStartupGateState extends State<AppStartupGate> {
  Widget? _application;
  bool _failed = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_starting || !mounted) return;
    _starting = true;
    try {
      await precacheImage(
        const AssetImage(AppLoadingIndicator.posterAsset),
        context,
      );
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final application = await widget.initialize();
      if (mounted) setState(() => _application = application);
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'startup'),
      );
      if (mounted) setState(() => _failed = true);
    } finally {
      _starting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_application != null) return _application!;
    return MaterialApp(
      title: CountryConfig.current.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final l10n = context.l10n;
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: _failed
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.appLoadingFailed),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: () {
                              setState(() => _failed = false);
                              _start();
                            },
                            child: Text(l10n.gameRetry),
                          ),
                        ],
                      )
                    : AppLoadingIndicator(label: l10n.appLoading),
              ),
            ),
          );
        },
      ),
    );
  }
}
