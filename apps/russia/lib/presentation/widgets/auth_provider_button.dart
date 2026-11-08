import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';

/// All providers keep the same geometry, including during loading.
class AuthProviderButton extends StatelessWidget {
  const AuthProviderButton({
    super.key,
    required this.svgAsset,
    required this.label,
    required this.onTap,
    this.svgColor,
    this.busy = false,
  });

  final String svgAsset;
  final String label;
  final VoidCallback? onTap;
  final Color? svgColor;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: Material(
        color: colors.searchFieldFill,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: busy
                      ? CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.primaryText,
                        )
                      : SvgPicture.asset(
                          svgAsset,
                          colorFilter: svgColor == null
                              ? null
                              : ColorFilter.mode(svgColor!, BlendMode.srcIn),
                        ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.primaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
