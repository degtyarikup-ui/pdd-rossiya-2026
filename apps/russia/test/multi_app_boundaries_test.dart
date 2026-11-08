import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../../tools/multi_app/check_boundaries.dart';

void main() {
  test('current repository obeys app and shared package boundaries', () {
    expect(checkBoundaries(Directory.current), isEmpty);
  });
  test('rejects shared assets, app dependency and cross-app import', () {
    final root = Directory.systemTemp.createTempSync('pdd-boundaries-');
    addTearDown(() => root.deleteSync(recursive: true));
    void write(String path, String content) {
      final file = File('${root.path}/$path');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    write('pubspec.yaml', 'name: pdd_app\n');
    write(
      'tools/multi_app/resource_policy.json',
      jsonEncode({
        'flutterAssetRoots': {'ru': []},
      }),
    );
    write('packages/ui/pubspec.yaml', 'name: ui\n');
    write('packages/ui/lib/ui.dart', 'class Token {}');
    expect(checkBoundaries(root), isEmpty);
    write(
      'packages/ui/pubspec.yaml',
      'name: ui\ndependencies:\n  pdd_app: any\nflutter:\n  assets: [assets/by/]\n',
    );
    write('packages/ui/lib/ui.dart', "export 'package:pdd_app/main.dart';\n");
    final errors = checkBoundaries(root);
    expect(errors.any((e) => e.contains('must not bundle')), isTrue);
    expect(errors.any((e) => e.contains('app dependency')), isTrue);
    expect(errors.any((e) => e.contains('cross-app import')), isTrue);
    write('packages/ui/lib/ui.dart', "export '../../../lib/main.dart';\n");
    expect(checkBoundaries(root).any((e) => e.contains('escapes lib')), isTrue);
  });
  test('rejects undeclared foreign assets in the application manifest', () {
    final root = Directory.systemTemp.createTempSync('pdd-assets-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/pubspec.yaml').writeAsStringSync(
      'name: pdd_app\nflutter:\n  assets: [assets/countries/by/]\n',
    );
    final policy = File('${root.path}/tools/multi_app/resource_policy.json');
    policy.parent.createSync(recursive: true);
    policy.writeAsStringSync(
      jsonEncode({
        'flutterAssetRoots': {'ru': []},
      }),
    );
    expect(checkBoundaries(root).single, contains('unregistered asset'));
  });
}
