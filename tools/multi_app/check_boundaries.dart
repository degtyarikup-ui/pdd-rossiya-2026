// Run from the repository root: dart run tools/multi_app/check_boundaries.dart
import 'dart:convert';
import 'dart:io';
import 'package:yaml/yaml.dart';

List<String> checkBoundaries(Directory root) {
  // Accept calls from a country app or from the workspace root.
  while (!File(
    '${root.path}/tools/multi_app/resource_policy.json',
  ).existsSync()) {
    final parent = root.parent;
    if (parent.path == root.path) {
      throw StateError('Workspace policy not found');
    }
    root = parent;
  }
  final errors = <String>[];
  final policy =
      jsonDecode(
            File(
              '${root.path}/tools/multi_app/resource_policy.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final registered = Map<String, String>.from(
    policy['applications'] as Map? ?? {'.': 'ru'},
  );
  final projects = <String, String>{...registered};
  for (final kind in ['apps', 'packages']) {
    final dir = Directory('${root.path}/$kind');
    if (!dir.existsSync()) continue;
    for (final item
        in dir.listSync(followLinks: false).whereType<Directory>()) {
      final name = item.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final path = '$kind/$name';
      projects[path] = kind == 'packages'
          ? 'shared'
          : (registered[path] ?? name);
    }
  }
  final appNames = <String>{};
  final manifests = <String, YamlMap>{};
  for (final entry in projects.entries) {
    final file = File('${root.path}/${entry.key}/pubspec.yaml');
    if (!file.existsSync()) {
      errors.add('Missing manifest: ${entry.key}');
      continue;
    }
    final yaml = loadYaml(file.readAsStringSync()) as YamlMap;
    manifests[entry.key] = yaml;
    if (entry.value != 'shared') appNames.add(yaml['name'] as String);
  }
  for (final entry in projects.entries) {
    final yaml = manifests[entry.key];
    if (yaml == null) continue;
    final owner = entry.value;
    final base = Directory('${root.path}/${entry.key}');
    final flutter = yaml['flutter'] as YamlMap?;
    if (owner == 'shared' &&
        (flutter?['assets'] != null || flutter?['fonts'] != null)) {
      errors.add('${entry.key}: shared packages must not bundle resources');
    }
    if (owner != 'shared') {
      final allowed = (policy['flutterAssetRoots'] as Map)[owner] as List?;
      if (allowed == null) {
        errors.add('Unregistered app owner: $owner');
        continue;
      }
      for (final asset in (flutter?['assets'] as List? ?? [])) {
        if (asset is! String || !allowed.contains(asset)) {
          errors.add('${entry.key}: unregistered asset declaration: $asset');
          continue;
        }
        final target = FileSystemEntity.typeSync('${base.path}/$asset');
        if (target == FileSystemEntityType.notFound) {
          errors.add('Missing asset: $asset');
        }
        if (asset.contains('..') || asset.startsWith('/')) {
          errors.add('Escaping asset: $asset');
        }
        final dir = Directory('${base.path}/$asset');
        if (dir.existsSync()) {
          for (final f in dir.listSync(recursive: true, followLinks: false)) {
            final path = f.path.replaceAll('\\', '/');
            for (final match in RegExp(
              r'/countries/([^/]+)/',
            ).allMatches(path)) {
              if (match[1] != owner) errors.add('Foreign resource: $path');
            }
          }
        }
      }
    }
    if (owner != 'shared') {
      final fonts =
          (policy['flutterFontAssets'] as Map?)?[owner] as List? ?? [];
      for (final family in (flutter?['fonts'] as List? ?? [])) {
        for (final font in (family['fonts'] as List? ?? [])) {
          final asset = font['asset'];
          if (!fonts.contains(asset)) {
            errors.add('${entry.key}: unregistered font: $asset');
          }
        }
      }
    }
    for (final section in [
      'dependencies',
      'dev_dependencies',
      'dependency_overrides',
    ]) {
      final deps = yaml[section] as YamlMap?;
      if (deps == null) continue;
      for (final dep in deps.entries) {
        if (appNames.contains(dep.key)) {
          errors.add('${entry.key}: app dependency ${dep.key}');
        }
        final value = dep.value;
        if (value is YamlMap && value['path'] is String) {
          final resolved = Directory(
            '${base.path}/${value['path']}',
          ).absolute.uri.normalizePath().path;
          final shared = Directory(
            '${root.path}/packages',
          ).absolute.uri.normalizePath().path;
          if (!resolved.startsWith(shared)) {
            errors.add(
              '${entry.key}: dependency outside shared packages: ${dep.key}',
            );
          }
        }
      }
    }
    final lib = Directory('${base.path}/lib');
    if (!lib.existsSync()) continue;
    for (final file
        in lib
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final text = file.readAsStringSync();
      for (final match in RegExp(
        r'''(?:import|export|part)\s+['"]([^'"]+)['"]''',
      ).allMatches(text)) {
        final uri = match[1]!;
        if (uri.startsWith('package:')) {
          final name = uri.substring(8).split('/').first;
          if (appNames.contains(name) && name != yaml['name']) {
            errors.add('${file.path}: cross-app import $uri');
          }
        } else if (!uri.startsWith('dart:')) {
          final resolved = file.parent.uri.resolve(uri).normalizePath().path;
          if (!resolved.startsWith(lib.absolute.uri.normalizePath().path)) {
            errors.add('${file.path}: import escapes lib: $uri');
          }
        }
      }
    }
  }
  return errors;
}

void main() {
  final errors = checkBoundaries(Directory.current);
  for (final error in errors) {
    stderr.writeln(error);
  }
  if (errors.isNotEmpty) {
    exitCode = 1;
  } else {
    stdout.writeln('App/package boundaries and resource declarations: OK');
  }
}
