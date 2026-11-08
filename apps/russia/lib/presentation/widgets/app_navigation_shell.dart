import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/layout/app_content_frame.dart';

typedef AppNavigationItem = ({
  IconData icon,
  IconData selectedIcon,
  String label,
});

/// Web desktop navigation shares destinations and state with the phone bar.
/// The content stays at the same element path when the browser is resized.
class AppNavigationShell extends StatelessWidget {
  const AppNavigationShell({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
    required this.child,
    this.fullscreen = false,
    this.desktopEnabled = kIsWeb,
    this.desktopFooterBuilder,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<AppNavigationItem> items;
  final Widget child;
  final bool fullscreen;
  final bool desktopEnabled;
  final Widget Function(bool extended)? desktopFooterBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop =
            desktopEnabled &&
            !fullscreen &&
            constraints.maxWidth >= 1100 &&
            constraints.maxHeight >= 500;
        final extended = MediaQuery.textScalerOf(context).scale(14) <= 20;
        return Scaffold(
          backgroundColor: colors.homeScreenBackground,
          body: Row(
            crossAxisAlignment: desktop
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.center,
            children: [
              if (desktop)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.cardBackground,
                    border: Border(right: BorderSide(color: colors.divider)),
                  ),
                  child: SafeArea(
                    right: false,
                    child: NavigationRail(
                      key: const ValueKey('desktop-navigation'),
                      extended: extended,
                      minWidth: 88,
                      minExtendedWidth: 216,
                      backgroundColor: Colors.transparent,
                      selectedIndex: selectedIndex,
                      onDestinationSelected: onSelected,
                      groupAlignment: -1,
                      trailing: desktopFooterBuilder == null
                          ? null
                          : Padding(
                              padding: const EdgeInsets.only(
                                top: 24,
                                bottom: 16,
                              ),
                              child: SizedBox(
                                width: extended ? 184 : 64,
                                child: desktopFooterBuilder!(extended),
                              ),
                            ),
                      indicatorColor: colors.accentSurface10,
                      selectedIconTheme: IconThemeData(color: colors.accent),
                      selectedLabelTextStyle: TextStyle(
                        fontFamily: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.fontFamily,
                        fontSize: 14,
                        color: colors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                      unselectedLabelTextStyle: TextStyle(
                        fontFamily: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.fontFamily,
                        fontSize: 14,
                        color: colors.secondaryText,
                      ),
                      leading: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 36),
                        child: extended
                            ? SizedBox(
                                width: 184,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.local_police_outlined,
                                      color: colors.accent,
                                      size: 32,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        CountryConfig.current.appTitle,
                                        maxLines: 2,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: colors.primaryText,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Icon(
                                Icons.local_police_outlined,
                                color: colors.accent,
                                size: 32,
                              ),
                      ),
                      destinations: [
                        for (final item in items)
                          NavigationRailDestination(
                            icon: Icon(item.icon),
                            selectedIcon: Icon(item.selectedIcon),
                            label: Text(item.label),
                          ),
                      ],
                    ),
                  ),
                )
              else
                const SizedBox.shrink(),
              Expanded(child: child),
            ],
          ),
          bottomNavigationBar: fullscreen || desktop
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(height: 1, color: colors.divider),
                    AppContentFrame(
                      child: NavigationBar(
                        selectedIndex: selectedIndex,
                        onDestinationSelected: onSelected,
                        destinations: [
                          for (final item in items)
                            NavigationDestination(
                              icon: Icon(item.icon),
                              selectedIcon: Icon(item.selectedIcon),
                              label: item.label,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
