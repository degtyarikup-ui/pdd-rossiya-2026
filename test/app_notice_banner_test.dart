import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/remote_notifications_service.dart';
import 'package:pdd_app/presentation/widgets/app_notice_widgets.dart';
import 'package:pdd_app/presentation/widgets/progress_panel_card.dart';

void main() {
  const emptyStats = {
    'correctAnswers': 0,
    'answeredQuestions': 0,
    'passedTickets': 0,
    'wrongQuestions': 0,
    'totalQuestions': 800,
    'totalTickets': 40,
  };

  Widget buildBannerBox({
    required double width,
    double textScale = 1.0,
    required AppNotice notice,
    required VoidCallback onTap,
    required VoidCallback onDismiss,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SizedBox(
            width: width,
            child: Stack(
              children: [
                const Visibility(
                  visible: false,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: ProgressPanelCard(stats: emptyStats),
                ),
                Positioned.fill(
                  child: AppNoticeBanner(
                    notice: notice,
                    onTap: onTap,
                    onDismiss: onDismiss,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('AppNoticeBanner with max 200 char body and 1.6x text scale does not overflow', (tester) async {
    final notice = AppNotice(
      id: 'c069e042-5b7b-40a0-b15e-b80c4444ce1d',
      title: 'Большое обновление билетов 2026 года с комментариями ГИБДД',
      body: 'В приложение добавлены новые комментарии к каждому билету категории AB и CD. Учите правила комфортно, следите за своей серией дней и успешно сдавайте теоретический экзамен с первой попытки!',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
      kind: 'banner',
      buttonText: 'Узнать больше и начать',
      action: NoticeAction.tickets,
    );

    await tester.pumpWidget(
      buildBannerBox(
        width: 320,
        textScale: 1.6,
        notice: notice,
        onTap: () {},
        onDismiss: () {},
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
