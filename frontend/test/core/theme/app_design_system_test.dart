import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/core/theme/app_colors.dart';
import 'package:top_coffee_pos/core/theme/app_theme.dart';
import 'package:top_coffee_pos/core/widgets/app_buttons.dart' as pos_ui;

void main() {
  Future<void> showControl(
    WidgetTester tester,
    Widget control, {
    bool dark = false,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(body: Center(child: control)),
    ),
  );

  testWidgets('button families keep callbacks and minimum touch targets', (
    tester,
  ) async {
    var presses = 0;
    final controls = <Widget>[
      pos_ui.PrimaryButton(
        onPressed: () => presses++,
        child: const Text('Save'),
      ),
      pos_ui.SecondaryButton(
        onPressed: () => presses++,
        child: const Text('Cancel'),
      ),
      pos_ui.OutlinedButton(
        onPressed: () => presses++,
        child: const Text('History'),
      ),
      pos_ui.DangerButton(
        onPressed: () => presses++,
        child: const Text('Delete'),
      ),
      pos_ui.DangerButton.outlinedIcon(
        onPressed: () => presses++,
        icon: const Icon(Icons.delete_outline),
        label: const Text('Clear Cart'),
      ),
      pos_ui.PosActionButton(
        onPressed: () => presses++,
        child: const Text('Pay'),
      ),
      pos_ui.IconButton(
        onPressed: () => presses++,
        icon: const Icon(Icons.add),
      ),
    ];
    for (final control in controls) {
      await showControl(tester, control);
      final size = tester.getSize(find.byWidget(control));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(
        size.height,
        greaterThanOrEqualTo(control is pos_ui.PosActionButton ? 56 : 48),
      );
      await tester.tap(find.byWidget(control));
      await tester.pump();
    }
    expect(presses, controls.length);
  });

  testWidgets(
    'loading keeps one accessible spinner and prevents duplicate taps',
    (tester) async {
      var presses = 0;
      await showControl(
        tester,
        pos_ui.PosActionButton.icon(
          onPressed: () => presses++,
          isLoading: true,
          icon: const Icon(Icons.payments_outlined),
          label: const Text('Pay'),
          loadingLabel: 'Processing payment',
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Processing payment'), findsOneWidget);
      semantics.dispose();
      expect(presses, 0);
    },
  );

  testWidgets('disabled button remains disabled in both themes', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      await showControl(
        tester,
        const pos_ui.PrimaryButton(onPressed: null, child: Text('Save')),
        dark: dark,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('tappable surfaces keep a 48px target and original action', (
    tester,
  ) async {
    var presses = 0;
    final control = pos_ui.ActionSurface(
      onTap: () => presses++,
      child: const Text('Choose customer'),
    );
    await showControl(tester, control);
    expect(
      tester.getSize(find.byWidget(control)).height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.text('Choose customer'));
    expect(presses, 1);
  });

  test('coffee palette and dark semantic colors stay centralized', () {
    expect(AppTheme.light.colorScheme.primary, AppColors.espresso);
    expect(AppTheme.light.scaffoldBackgroundColor, AppColors.cream);
    expect(AppTheme.dark.brightness, Brightness.dark);
    expect(AppTheme.dark.colorScheme.primary, AppColors.caramel);
    expect(
      AppColors.forScheme(AppTheme.dark.colorScheme, AppColors.success),
      AppColors.darkSuccess,
    );
    expect(
      AppColors.forScheme(AppTheme.dark.colorScheme, AppColors.warning),
      AppColors.darkWarning,
    );
    expect(
      AppColors.forScheme(AppTheme.dark.colorScheme, AppColors.info),
      AppColors.darkInfo,
    );
  });
}
