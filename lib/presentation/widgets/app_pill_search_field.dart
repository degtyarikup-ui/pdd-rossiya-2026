import 'package:flutter/material.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/core/constants/app_colors.dart';

/// iOS-style pill search field (same look on Signs / PDD main screens).
class AppPillSearchField extends StatefulWidget {
  const AppPillSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hintText,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? hintText;

  @override
  State<AppPillSearchField> createState() => _AppPillSearchFieldState();
}

class _AppPillSearchFieldState extends State<AppPillSearchField> {
  static const double _radius = 999;

  late final OutlineInputBorder _shape = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_radius),
    borderSide: BorderSide.none,
  );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerText);
  }

  @override
  void didUpdateWidget(covariant AppPillSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerText);
      widget.controller.addListener(_onControllerText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerText);
    super.dispose();
  }

  void _onControllerText() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.isNotEmpty;
    return TextField(
      controller: widget.controller,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.primaryText,
      ),
      cursorColor: AppColors.accent,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hintText ?? appL10n.search,
        hintStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.secondaryText.withValues(alpha: 0.85),
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 22,
          color: AppColors.secondaryText.withValues(alpha: 0.75),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 48,
          minHeight: 48,
        ),
        suffixIcon: !hasText
            ? null
            : IconButton(
                onPressed: () {
                  widget.controller.clear();
                  widget.onChanged('');
                },
                icon: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: AppColors.secondaryText.withValues(alpha: 0.75),
                ),
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
        filled: true,
        fillColor: AppColors.searchFieldFill,
        border: _shape,
        enabledBorder: _shape,
        focusedBorder: _shape,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
}
