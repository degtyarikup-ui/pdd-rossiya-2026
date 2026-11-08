import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Единый огонёк приложения из `assets/images/fire.svg`.
///
/// Исходный SVG чёрный; перекрашивается в нужный цвет через srcIn —
/// белый на активном дне, светло-серый на пустом, золотой в поздравлении.
class FlameIcon extends StatelessWidget {
  final double size;
  final Color color;

  const FlameIcon({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/fire.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
