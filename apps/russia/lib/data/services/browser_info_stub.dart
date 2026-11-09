import 'package:pdd_app/data/services/web_checkout_route.dart';

/// Реализация по умолчанию (Android/iOS/desktop) — на вебе подменяется
/// [browser_info_web.dart] через условный импорт в install_reporter.dart.
Map<String, String> browserInfoFields() => const {};

Map<String, String> browserAcquisitionFields() => const {};

/// Возврат с формы оплаты бывает только на вебе.
({String result, String order})? takePaymentReturn() => null;

String? takeReferralParam() => null;

void setWebCheckoutAddress(WebCheckoutRoute checkout) {}
