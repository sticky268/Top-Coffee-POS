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
class PageAppBar extends StatelessWidget implements PreferredSizeWidget {
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
  Widget build(BuildContext context) {
    final navigation = PageNavigation.maybeOf(context);
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return AppBar(
      title: title,
      actions: actions,
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
      bottom: bottom,
      toolbarHeight: toolbarHeight,
      titleSpacing: titleSpacing,
      centerTitle: centerTitle,
    );
  }
}
