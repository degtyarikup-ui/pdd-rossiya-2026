import 'package:flutter/widgets.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/browser_info_stub.dart'
    if (dart.library.js_interop) 'package:pdd_app/data/services/browser_info_web.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/app_toast.dart';

/// Возврат с формы оплаты на сайте (`/app/?pay=done&order=…`): сервер
/// перепроверяет платёж у платёжного сервиса и начисляет срок, приложение
/// показывает итог. Если подтверждение ещё не пришло — Премиум включится
/// сам: главный экран раз в 5 минут опрашивает статус аккаунта.
Future<void> handleWebPaymentReturn(BuildContext context) async {
  final ret = takePaymentReturn();
  if (ret == null) return;
  if (ret.result != 'done') {
    if (context.mounted) {
      AppToast.show(context, appL10n.webPayCanceled);
    }
    return;
  }
  // Сессия восстанавливается при запуске — ждём её недолго.
  for (var i = 0; i < 20 && !AuthService.instance.hasServerSession; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  String? status;
  for (var attempt = 0; attempt < 6; attempt++) {
    status = await PremiumService.instance.checkWebPayment(ret.order);
    if (status != null && status != 'pending') break;
    await Future<void>.delayed(const Duration(seconds: 5));
  }
  if (!context.mounted) return;
  switch (status) {
    case 'confirmed':
      AppToast.show(
        context,
        appL10n.webPaySuccess,
        type: AppToastType.success,
      );
    case 'canceled':
      AppToast.show(context, appL10n.webPayCanceled);
    default:
      AppToast.show(context, appL10n.webPayPending);
  }
}
