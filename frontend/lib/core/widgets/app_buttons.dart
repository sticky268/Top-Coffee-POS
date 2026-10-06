import 'package:flutter/material.dart' as material;

/// Brand controls retain Material focus, keyboard activation, semantics and
/// animated ink ripples. Loading affects only presentation and tap availability.
enum _ButtonKind { primary, secondary, outlined, danger, action }

class _BrandButton extends material.StatelessWidget {
  const _BrandButton({
    super.key,
    required this.kind,
    required this.onPressed,
    this.child,
    this.icon,
    this.label,
    this.style,
    this.isLoading = false,
    this.loadingLabel = 'Loading',
  }) : assert(child != null || label != null);

  final _ButtonKind kind;
  final material.VoidCallback? onPressed;
  final material.Widget? child;
  final material.Widget? icon;
  final material.Widget? label;
  final material.ButtonStyle? style;
  final bool isLoading;
  final String loadingLabel;

  @override
  material.Widget build(material.BuildContext context) {
    final scheme = material.Theme.of(context).colorScheme;
    final danger = kind == _ButtonKind.danger;
    final height = kind == _ButtonKind.action ? 56.0 : 48.0;
    // Layout tokens win over legacy compact styles so all controls stay usable.
    final effectiveStyle = (style ?? const material.ButtonStyle()).copyWith(
      minimumSize: material.WidgetStatePropertyAll(material.Size(48, height)),
      padding: const material.WidgetStatePropertyAll(
        material.EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
      shape: const material.WidgetStatePropertyAll(
        material.RoundedRectangleBorder(
          borderRadius: material.BorderRadius.all(material.Radius.circular(14)),
        ),
      ),
      textStyle: material.WidgetStatePropertyAll(
        material.TextStyle(
          fontFamily: 'Inter',
          fontWeight: material.FontWeight.w600,
          fontSize: kind == _ButtonKind.action ? 16 : 14,
        ),
      ),
      backgroundColor: danger
          ? material.WidgetStateProperty.resolveWith(
              (states) => states.contains(material.WidgetState.disabled)
                  ? scheme.onSurface.withValues(alpha: 0.12)
                  : scheme.error,
            )
          : style?.backgroundColor,
      foregroundColor: danger
          ? material.WidgetStateProperty.resolveWith(
              (states) => states.contains(material.WidgetState.disabled)
                  ? scheme.onSurface.withValues(alpha: 0.38)
                  : scheme.onError,
            )
          : style?.foregroundColor,
      visualDensity: material.VisualDensity.standard,
      tapTargetSize: material.MaterialTapTargetSize.padded,
      animationDuration: const Duration(milliseconds: 180),
    );
    final enabledCallback = isLoading ? null : onPressed;
    final content = isLoading
        ? material.Semantics(
            label: loadingLabel,
            liveRegion: true,
            child: material.SizedBox.square(
              dimension: 18,
              child: material.CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        : child ?? label!;
    final leading = isLoading ? null : icon;
    switch (kind) {
      case _ButtonKind.secondary:
        return leading == null
            ? material.TextButton(
                onPressed: enabledCallback,
                style: effectiveStyle,
                child: content,
              )
            : material.TextButton.icon(
                onPressed: enabledCallback,
                style: effectiveStyle,
                icon: leading,
                label: content,
              );
      case _ButtonKind.outlined:
        return leading == null
            ? material.OutlinedButton(
                onPressed: enabledCallback,
                style: effectiveStyle,
                child: content,
              )
            : material.OutlinedButton.icon(
                onPressed: enabledCallback,
                style: effectiveStyle,
                icon: leading,
                label: content,
              );
      case _ButtonKind.primary:
      case _ButtonKind.danger:
      case _ButtonKind.action:
        return leading == null
            ? material.FilledButton(
                onPressed: enabledCallback,
                style: effectiveStyle,
                child: content,
              )
            : material.FilledButton.icon(
                onPressed: enabledCallback,
                style: effectiveStyle,
                icon: leading,
                label: content,
              );
    }
  }
}

class PrimaryButton extends _BrandButton {
  const PrimaryButton({
    super.key,
    required super.onPressed,
    required material.Widget child,
    super.style,
    super.isLoading,
    super.loadingLabel,
  }) : super(kind: _ButtonKind.primary, child: child);

  const PrimaryButton.icon({
    super.key,
    required super.onPressed,
    required material.Widget icon,
    required material.Widget label,
    super.style,
    super.isLoading,
    super.loadingLabel,
  }) : super(kind: _ButtonKind.primary, icon: icon, label: label);
}

class SecondaryButton extends _BrandButton {
  const SecondaryButton({
    super.key,
    required super.onPressed,
    required material.Widget child,
    super.style,
    super.isLoading,
    super.loadingLabel,
  }) : super(kind: _ButtonKind.secondary, child: child);

  const SecondaryButton.icon({
    super.key,
    required super.onPressed,
    required material.Widget icon,
    required material.Widget label,
    super.style,
    super.isLoading,
    super.loadingLabel,
  }) : super(kind: _ButtonKind.secondary, icon: icon, label: label);
}

class OutlinedButton extends _BrandButton {
  const OutlinedButton({
    super.key,
    required super.onPressed,
    required material.Widget child,
    super.style,
    super.isLoading,
    super.loadingLabel,
  }) : super(kind: _ButtonKind.outlined, child: child);

  const OutlinedButton.icon({
    super.key,
    required super.onPressed,
    required material.Widget icon,
    required material.Widget label,
    super.style,
    super.isLoading,
    super.loadingLabel,
  }) : super(kind: _ButtonKind.outlined, icon: icon, label: label);
}

class DangerButton extends _BrandButton {
  const DangerButton({
    super.key,
    required super.onPressed,
    required material.Widget child,
    super.style,
    super.isLoading,
    super.loadingLabel,
  }) : super(kind: _ButtonKind.danger, child: child);

  const DangerButton.icon({
    super.key,
    required super.onPressed,
    required material.Widget icon,
    required material.Widget label,
    super.style,
    super.isLoading,
    super.loadingLabel,
  }) : super(kind: _ButtonKind.danger, icon: icon, label: label);
}

class PosActionButton extends _BrandButton {
  const PosActionButton({
    super.key,
    required super.onPressed,
    required material.Widget child,
    super.style,
    super.isLoading,
    super.loadingLabel,
  }) : super(kind: _ButtonKind.action, child: child);

  const PosActionButton.icon({
    super.key,
    required super.onPressed,
    required material.Widget icon,
    required material.Widget label,
    super.style,
    super.isLoading,
    super.loadingLabel,
  }) : super(kind: _ButtonKind.action, icon: icon, label: label);
}

class IconButton extends material.StatelessWidget {
  const IconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.visualDensity,
    this.isLoading = false,
  });

  final material.VoidCallback? onPressed;
  final material.Widget icon;
  final String? tooltip;
  // Accepted for drop-in migration; controls still enforce a 48px touch target.
  final material.VisualDensity? visualDensity;
  final bool isLoading;

  @override
  material.Widget build(material.BuildContext context) => material.IconButton(
    onPressed: isLoading ? null : onPressed,
    tooltip: tooltip,
    visualDensity: material.VisualDensity.standard,
    constraints: const material.BoxConstraints(minWidth: 48, minHeight: 48),
    icon: isLoading
        ? const material.SizedBox.square(
            dimension: 18,
            child: material.CircularProgressIndicator(strokeWidth: 2),
          )
        : icon,
  );
}

/// A card or row that acts as a button, with the same interaction language.
class ActionSurface extends material.StatelessWidget {
  const ActionSurface({
    super.key,
    required this.onTap,
    required this.child,
    this.borderRadius = const material.BorderRadius.all(
      material.Radius.circular(14),
    ),
  });

  final material.VoidCallback? onTap;
  final material.Widget child;
  final material.BorderRadius? borderRadius;

  @override
  material.Widget build(material.BuildContext context) => material.InkWell(
    onTap: onTap,
    borderRadius: borderRadius,
    child: material.ConstrainedBox(
      constraints: const material.BoxConstraints(minHeight: 48),
      child: child,
    ),
  );
}
