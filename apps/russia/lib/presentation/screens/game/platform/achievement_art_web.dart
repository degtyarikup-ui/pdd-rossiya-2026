import 'dart:ui_web' as ui_web;

import 'package:web/web.dart' as web;

/// В вебе игра сама скачивает нужный значок из ассетов приложения, поэтому
/// достаточно абсолютного адреса папки (игра открыта в своём iframe).
Future<String> prepareAchievementArt(Iterable<String> assetKeys) async =>
    Uri.parse(web.document.baseURI)
        .resolve(ui_web.assetManager.getAssetUrl('assets/images/achievements/'))
        .toString();
