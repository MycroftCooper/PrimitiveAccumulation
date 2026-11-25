import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primitive_accumulation/core/book.dart';
import 'package:primitive_accumulation/core/theme.dart';
import 'package:primitive_accumulation/features/ledger.dart';
import 'package:primitive_accumulation/shared/charts.dart';

void main() {
  testWidgets(
    'dark skin, stock chart drilldown and return preserve selected view',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final book = Book.example();
      addTearDown(book.dispose);
      for (final skin in Skin.values) {
        final light = wealthTheme(skin, Brightness.light),
            dark = wealthTheme(skin, Brightness.dark);
        expect(
          light.scaffoldBackgroundColor,
          isNot(dark.scaffoldBackgroundColor),
        );
        expect(light.extension<WealthColors>()!.stage, skin.stage);
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: wealthTheme(Skin.dusk, Brightness.dark),
          builder: (_, child) => BookScope(book: book, child: child!),
          home: const Scaffold(body: LedgerPage(initialItem: 'sample-3')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026-05-15\n第 1 期'));
      await tester.pumpAndSettle();
      expect(find.text('2026-05-15 · 第 1 期'), findsOneWidget);
      expect(find.text('¥150,000'), findsWidgets);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(BalanceChart), findsOneWidget);
      await tester.tap(find.text('构成占比'));
      await tester.pumpAndSettle();
      expect(find.text('股票占总资产'), findsOneWidget);
      expect(find.text('35.5%'), findsOneWidget);
      expect(find.byType(BalanceChart), findsNothing);
    },
  );
}
