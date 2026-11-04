/// Calendar season passed to every Godot game at launch. Store builds ignore
/// preview overrides; December 1 through the end of February is winter.
abstract final class GameSeason {
  static List<String> launchArguments(
    List<String> arguments,
    DateTime now, {
    bool debug = const bool.fromEnvironment('GAME_DEBUG'),
    String preview = const String.fromEnvironment('DEV_SEASON'),
  }) {
    if (debug && arguments.any((arg) => arg.startsWith('--season='))) {
      return arguments;
    }
    final month = now.month;
    final calendar = month == 12 || month <= 2
        ? 'winter'
        : month >= 9
        ? 'autumn'
        : 'summer';
    final season = debug
        ? (const {'summer', 'autumn', 'winter'}.contains(preview)
              ? preview
              : 'winter')
        : calendar;
    return [
      ...arguments.where((arg) => !arg.startsWith('--season=')),
      '--season=$season',
    ];
  }
}
