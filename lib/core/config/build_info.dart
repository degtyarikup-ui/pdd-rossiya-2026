import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Provides build metadata, test build identification, and git commit hash resolution.
class BuildInfo {
  BuildInfo._();

  static const MethodChannel _channel = MethodChannel('pdd/build_info');

  /// Compile-time commit hash from `--dart-define=GIT_COMMIT=...`.
  static const String _compileTimeCommit = String.fromEnvironment('GIT_COMMIT');

  static String? _cachedCommit;
  static String? _testOverrideCommit;

  @visibleForTesting
  static void overrideCommitForTesting(String? commit) {
    _testOverrideCommit = commit;
  }

  /// Whether this build is considered a test/development build:
  /// - `GIT_COMMIT` define is present and not empty
  /// - `GAME_DEBUG` define is enabled
  /// - package name ends with `.dev` (Android test build with `-Pdev`)
  /// - debug mode (`kDebugMode`), unless package name explicitly represents a store release
  static bool isTestBuild({PackageInfo? packageInfo}) {
    if (_testOverrideCommit != null) return true;
    if (_compileTimeCommit.isNotEmpty) return true;
    if (const bool.fromEnvironment('GAME_DEBUG')) return true;
    if (packageInfo != null) {
      return packageInfo.packageName.endsWith('.dev');
    }
    return kDebugMode;
  }

  /// Resolves the git commit hash for test builds.
  /// Returns empty string if not a test build or commit could not be determined.
  static Future<String> getGitCommit({PackageInfo? packageInfo}) async {
    if (_testOverrideCommit != null) return _testOverrideCommit!;
    if (!isTestBuild(packageInfo: packageInfo)) return '';
    if (_cachedCommit != null) return _cachedCommit!;

    if (_compileTimeCommit.isNotEmpty) {
      _cachedCommit = _compileTimeCommit;
      return _compileTimeCommit;
    }

    if (!kIsWeb) {
      try {
        final nativeCommit = await _channel.invokeMethod<String>('gitCommit');
        if (nativeCommit != null && nativeCommit.isNotEmpty) {
          _cachedCommit = nativeCommit;
          return nativeCommit;
        }
      } on (PlatformException, MissingPluginException) {
        // Platform channel not available or not implemented
      }
    }

    return '';
  }
}
