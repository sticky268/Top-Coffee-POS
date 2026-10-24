import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../branch/current_branch_provider.dart';
import '../theme/coffee_studio_theme.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/auth_state.dart';
import 'package:flutter/material.dart';

/// The shell supplies drawer access without consuming a second toolbar row.
class PageNavigation extends InheritedWidget {
  const PageNavigation({
    super.key,
    required this.openMenu,
    required super.child,
  });

  final VoidCallback openMenu;

  static PageNavigation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageNavigation>();

  @override
  bool updateShouldNotify(PageNavigation oldWidget) =>
      oldWidget.openMenu != openMenu;
}

/// Keeps the usual back button on pushed pages and a menu on root pages.
class PageAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const PageAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.toolbarHeight,
    this.titleSpacing,
    this.centerTitle,
    this.automaticallyImplyLeading = true,
  });

  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final double? toolbarHeight;
  final double? titleSpacing;
  final bool? centerTitle;
  final bool automaticallyImplyLeading;

  @override
  Size get preferredSize => Size.fromHeight(
      (toolbarHeight ?? kToolbarHeight) + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigation = PageNavigation.maybeOf(context);
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final studio = CoffeeStudioTheme.active(context);
    final base = Theme.of(context);
    final toolbarTheme = base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: Colors.white,
        onPrimary: const Color(0xFF3E2723),
        onSurface: Colors.white,
        onSurfaceVariant: const Color(0xFFF5EEE6),
        surface: const Color(0xFF3E2723),
        outlineVariant: const Color(0xFF9B8175),
      ),
      textButtonTheme: TextButtonThemeData(
          style: base.textButtonTheme.style?.copyWith(
              foregroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.disabled)
                      ? Colors.white38
                      : Colors.white))),
    );
    Widget toolbarControl(Widget control) =>
        studio ? Theme(data: toolbarTheme, child: control) : control;
    return AppBar(
      title: title,
      actions: [
        for (final action in actions ?? <Widget>[]) toolbarControl(action),
        if (CoffeeStudioTheme.active(context) &&
            MediaQuery.sizeOf(context).width >= 900 &&
            MediaQuery.textScalerOf(context).scale(14) <= 20) ...[
          Builder(builder: (context) {
            final branch = ref.watch(currentBranchProvider);
            final auth = ref.watch(authControllerProvider);
            final name = auth is AuthAuthenticated ? auth.user.name : '';
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.location_on_outlined, size: 17),
                const SizedBox(width: 6),
                Text(branch?.name ?? 'Select branch',
                    style: const TextStyle(fontSize: 13)),
                if (name.isNotEmpty) ...[
                  const SizedBox(width: 24),
                  CircleAvatar(
                      radius: 15,
                      backgroundColor: const Color(0xFFC8A165),
                      child: Text(name.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                              color: Color(0xFF3E2723), fontSize: 13))),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13))),
                ],
              ]),
            );
          }),
        ],
      ],
      leading: leading ??
          (automaticallyImplyLeading && !canPop && navigation != null
              ? IconButton(
                  tooltip:
                      MaterialLocalizations.of(context).openAppDrawerTooltip,
                  onPressed: navigation.openMenu,
                  icon: const Icon(Icons.menu),
                )
              : null),
      automaticallyImplyLeading: automaticallyImplyLeading,
      bottom: studio && bottom != null
          ? PreferredSize(
              preferredSize: bottom!.preferredSize,
              child: toolbarControl(bottom!))
          : bottom,
      toolbarHeight: toolbarHeight,
      titleSpacing: titleSpacing,
      centerTitle: centerTitle,
    );
  }
}
