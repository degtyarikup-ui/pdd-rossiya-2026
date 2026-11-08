import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/config/game_season.dart';

void main() {
  test('store games switch from autumn to winter at December 1', () {
    for (final mode in [
      '',
      '--crossroads',
      '--regulator',
      '--parking',
      '--violator',
    ]) {
      final args = [if (mode.isNotEmpty) mode, '--lang=ru'];
      expect(
        GameSeason.launchArguments(
          args,
          DateTime(2026, 11, 30, 23, 59, 59),
          debug: false,
        ),
        [...args, '--season=autumn'],
      );
      expect(
        GameSeason.launchArguments(args, DateTime(2026, 12, 1), debug: false),
        [...args, '--season=winter'],
      );
    }
  });

  test('store launch ignores stale preview arguments and dev season', () {
    expect(
      GameSeason.launchArguments(
        ['--parking', '--season=winter'],
        DateTime(2026, 11, 5),
        debug: false,
        preview: 'winter',
      ),
      ['--parking', '--season=autumn'],
    );
    expect(
      GameSeason.launchArguments(
        ['--season=summer'],
        DateTime(2026, 12, 1),
        debug: false,
      ),
      ['--season=winter'],
    );
  });

  test('winter continues through February and ends in March', () {
    for (final date in [
      DateTime(2027, 1, 1),
      DateTime(2027, 2, 28, 23, 59),
      DateTime(2028, 2, 29),
    ]) {
      expect(GameSeason.launchArguments([], date, debug: false), [
        '--season=winter',
      ]);
    }
    expect(GameSeason.launchArguments([], DateTime(2027, 3, 1), debug: false), [
      '--season=summer',
    ]);
  });

  test('dev builds retain winter preview and explicit season selection', () {
    final date = DateTime(2026, 11, 5);
    expect(GameSeason.launchArguments([], date, debug: true), [
      '--season=winter',
    ]);
    expect(
      GameSeason.launchArguments([], date, debug: true, preview: 'summer'),
      ['--season=summer'],
    );
    expect(GameSeason.launchArguments(['--season=autumn'], date, debug: true), [
      '--season=autumn',
    ]);
  });
}
