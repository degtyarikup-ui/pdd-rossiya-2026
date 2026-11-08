# App isolation gates

Run from the repository root after `flutter pub get`:

```sh
dart tools/multi_app/check_boundaries.dart
python3 -m unittest discover -s tools/multi_app -p 'test_*.py'
python3 tools/multi_app/check_artifact.py build/app/outputs/flutter-apk/app-ru-release.apk --country ru
python3 tools/multi_app/check_artifact.py build/web --country ru --profile ru-web
python3 tools/multi_app/check_artifact.py ios/Godot/game.pck --country ru --profile ru-ios-game
```

`resource_policy.json` assigns current content conservatively to RU. Shared UI
has no bundled resources. New asset declarations and new apps require explicit
registration. Country codes are distinct from UI languages: RU English content
is still RU content. The source gate checks package dependencies, relative
imports and asset declarations; it does not determine legal correctness.

The artifact gate reads APK/AAB/IPA ZIP entries, loose web/Android resources,
and standalone/nested unencrypted Godot PCK v2/v3/v4. It rejects unsupported
or encrypted packs, foreign country paths and foreign `scene.json` country
metadata. PCK layout reference:
https://github.com/godotengine/godot/blob/master/core/io/file_access_pack.cpp
It cannot infer the jurisdiction of an unlabelled image/audio file: that is why
content roots have explicit ownership, and BY gets its own assets and exporters.

Size profiles compare uncompressed contents, with 15% headroom over the recorded
local baseline. Container size is reported separately; store download size is
unknown (device splits/compression differ). Do not compare a dev ARM64 APK to
a universal store APK, and do not automatically raise limits after a failure.
The checked-in baseline describes existing local artifacts, not a new release.

Source gates run in build.sh, build_dev.sh, Android preBuild and the Xcode Flutter
build phase. Thus direct Android/iOS Flutter builds get the same source gate.
Android preBuild also audits existing loose Godot assets; the iOS copy phase
audits the existing PCK before copying it, so stale foreign packs cannot bypass
the exporter checks through direct Flutter commands.
Godot exporters check generated content before replacing the previous output.
APK/AAB release and dev build commands audit final artifacts; web release and
APP_BUILD deployment audit web contents, including PCK. Direct Flutter web/bundle
commands have no custom hook: explicitly run the source and artifact checks;
deployment through the supported scripts still enforces the artifact check.
The existing iOS IPA command uploads: never run it as a local test. Validate
locally with `flutter build ios --release --no-codesign` and audit the .app.

CI runs the source gate and adversarial tests without signing keys or deployment.
Full native release smoke tests and actual-device update tests remain necessary.
