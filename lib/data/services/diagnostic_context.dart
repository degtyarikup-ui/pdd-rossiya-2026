/// Diagnostic fields contain codes, counts and application source locations.
/// Raw messages, SDK details, URLs and arbitrary stack lines are never retained.
class DiagnosticContext {
  static const productIds = {
    'u.pdd.pddApp.premium.week',
    'ru.pdd.pddApp.sub.3months',
    'ru.pdd.pddapp.sub.week',
    'ru.pdd.pddapp.sub.3months',
  };

  static Map<String, dynamic> sanitize(Map<String, dynamic>? value) {
    final input = value ?? const <String, dynamic>{};
    final result = <String, dynamic>{};
    for (final entry in {
      'phase': {'background', 'paywall', 'purchase'},
      'stage': {'availability', 'query', 'framework', 'unhandled'},
      'sdkSource': {'app_store', 'google_play'},
    }.entries) {
      if (entry.value.contains(input[entry.key])) {
        result[entry.key] = input[entry.key];
      }
    }
    for (final key in [
      'attempt',
      'requestedCount',
      'returnedCount',
      'missingCount',
    ]) {
      final v = input[key];
      if (v is int && v >= 0 && v <= 100) result[key] = v;
    }
    final hash = input['sdkCodeHash'];
    if (hash is String && RegExp(r'^[a-f0-9]{16}$').hasMatch(hash)) {
      result['sdkCodeHash'] = hash;
    }
    if (input['missingIds'] is List) {
      result['missingIds'] = (input['missingIds'] as List)
          .whereType<String>()
          .where((v) => v.length <= 160)
          .where(productIds.contains)
          .toSet()
          .take(4)
          .toList();
    }
    if (input['frames'] is List) {
      result['frames'] = (input['frames'] as List)
          .whereType<String>()
          .where((v) => v.length <= 160)
          .where(
            (v) => RegExp(
              r'^package:pdd_app/(?:[a-zA-Z0-9_]+/)*[a-zA-Z0-9_]+\.dart(?::\d{1,6}(?::\d{1,5})?)?$',
            ).hasMatch(v),
          )
          .take(6)
          .toList();
    }
    return result;
  }

  static List<String> frames(StackTrace? stack) => stack == null
      ? []
      : RegExp(
              r'package:pdd_app/(?:[a-zA-Z0-9_]+/)*[a-zA-Z0-9_]+\.dart(?::\d{1,6}(?::\d{1,5})?)?',
            )
            .allMatches(stack.toString())
            .map((m) => m.group(0)!)
            .where((v) => v.length <= 160)
            .toSet()
            .take(6)
            .toList();
}
