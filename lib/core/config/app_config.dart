class SupabaseConfig {
  SupabaseConfig._();

  static const String url = 'https://pyqimpwgcnafctlwjtbt.supabase.co';
  /// Публичный (anon / publishable) ключ — его видно в приложении, это нормально.
  static const String anonKey = 'sb_publishable_i1xStb4JL56ErCxf7xeLVg_3EGbEnO0';
  // Service Role никогда не храните в приложении — только на сервере (Edge Functions, свой бэкенд).
}

/// Google Sign-In на Android: тот же **Web client** ID, что в Supabase
/// (Authentication → Providers → Google → Client ID). Без него часто нет id_token.
class GoogleOAuthConfig {
  GoogleOAuthConfig._();

  static const String webClientId =
      '92147521898-0cjopbppkl7v80shup9lhjtmfmcmbekb.apps.googleusercontent.com';
}

class YookassaConfig {
  YookassaConfig._();

  static const String shopId = 'YOUR_SHOP_ID';
  static const String secretKey = 'YOUR_SECRET_KEY';
  static const String returnUrl = 'pddapp://payment_result';
}
