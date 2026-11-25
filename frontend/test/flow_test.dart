import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primitive_accumulation/app/app.dart';
import 'package:primitive_accumulation/core/book.dart';
import 'package:primitive_accumulation/core/theme.dart';
import 'package:primitive_accumulation/shared/charts.dart';
import 'package:primitive_accumulation/shared/pig_bank.dart';

void main() {
  testWidgets('portrait stocktake, receipt, detail, note and chart paging', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final book = Book.example();
    addTearDown(book.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: wealthTheme(Skin.grove, Brightness.light),
        builder: (_, nav) => BookScope(book: book, child: nav!),
        home: HomeShell(lock: () {}),
      ),
    );
    await t.pumpAndSettle();
    Future<void> tap(String label) async {
      final f = find.text(label).last;
      await t.ensureVisible(f);
      await t.tap(f);
      await t.pumpAndSettle();
    }

    expect(find.byType(PigBank), findsOneWidget);
    await tap('盘点一次');
    await t.enterText(find.widgetWithText(TextField, '当前余额（元）'), '92252');
    await tap('核对本期');
    await tap('提交并看回执');
    expect(book.latest!.net, 72243800);
    expect(find.text('+10,000 元'), findsWidgets);
    await tap('活期存款');
    expect(find.text('¥82,252'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '测试回顾');
    await tap('保存到回顾');
    expect(book.note(3), '测试回顾');
    await t.pageBack();
    await t.pumpAndSettle();
    await tap('账本');
    await tap('按条目查');
    expect(find.byType(BalanceChart), findsOneWidget);
    expect(find.byType(ShareChart), findsNothing);
    await tap('构成占比');
    expect(find.byType(ShareChart), findsOneWidget);
    expect(find.byType(BalanceChart), findsNothing);
  });
}
