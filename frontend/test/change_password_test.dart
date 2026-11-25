import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primitive_accumulation/core/book.dart';
import 'package:primitive_accumulation/core/models.dart';
import 'package:primitive_accumulation/core/theme.dart';
import 'package:primitive_accumulation/features/settings.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late String path;
  const old = "旧'密码-123", next = "新'密码-🔑";
  setUp(() {
    dir = Directory.systemTemp.createTempSync('book-password-');
    path = '${dir.path}/book.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'rotate an existing encrypted ledger and keep snapshots, preferences and draft',
    () {
      // Seed a vault using the original quoted-key format.
      final legacy = sqlite3.open(path);
      legacy.execute("PRAGMA key='旧''密码-123'");
      legacy.execute(
        'CREATE TABLE snapshots(id INTEGER PRIMARY KEY, time INTEGER NOT NULL, entries TEXT NOT NULL)',
      );
      legacy.close();
      final book = Book.open(path, old);
      final stale = Book.open(path, old);
      addTearDown(stale.dispose);
      book.saveEntry(
        const Entry(id: 'a', name: '现金', category: '存款', cents: 2020),
      );
      final first = book.commit();
      book.saveNote(first.id, '回顾');
      book.setGoal(WealthGoal('目标', 50000, first.id, ''));
      book.appearance(ThemeMode.dark, 'dusk');
      book.saveEntry(
        const Entry(id: 'a', name: '现金', category: '存款', cents: 2030),
      );
      final before = book.exportData().toJson();
      expect(book.verifyPassword('wrong-password'), isFalse);
      expect(
        () => book.changePassword('wrong-password', next),
        throwsA(isA<SqliteException>()),
      );
      expect(() => book.changePassword(old, ''), throwsFormatException);
      expect(book.verifyPassword(old), isTrue);
      book.changePassword(old, next);
      expect(
        () => stale.saveNote(first.id, 'stale'),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => stale.changePassword(old, 'another-key'),
        throwsA(isA<SqliteException>()),
      );
      expect(book.exportData().toJson(), before);
      book.dispose();
      expect(() => Book.open(path, old), throwsA(isA<SqliteException>()));
      final unlocked = Book.open(path, next);
      addTearDown(unlocked.dispose);
      expect(unlocked.exportData().toJson(), before);
      expect(unlocked.commit().net, 2030);
    },
  );

  test('a busy ledger can still use the original password and retry', () {
    final book = Book.open(path, old);
    addTearDown(book.dispose);
    final reader = sqlite3.open(path);
    try {
      reader.execute("PRAGMA key='旧''密码-123'");
      reader.execute('BEGIN');
      reader.select('SELECT count(*) FROM snapshots');
      expect(
        () => book.changePassword(old, next),
        throwsA(isA<SqliteException>()),
      );
      expect(book.verifyPassword(old), isTrue);
      expect(book.verifyPassword(next), isFalse);
    } finally {
      reader.close();
    }
    book.changePassword(old, next);
    expect(book.verifyPassword(next), isTrue);
  });

  testWidgets(
    'settings verifies old password before accepting two matching new passwords',
    (tester) async {
      final book = Book.open(path, old);
      addTearDown(book.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: wealthTheme(Skin.grove, Brightness.light),
          builder: (_, child) => BookScope(book: book, child: child!),
          home: SettingsPage(afterLock: (_) {}, sessionActive: () => true),
        ),
      );
      await tester.tap(find.text('修改账本密码'));
      await tester.pumpAndSettle();
      expect(find.text('新密码'), findsNothing);
      await tester.enterText(find.byType(TextField), 'wrong-password');
      await tester.tap(find.text('验证旧密码'));
      await tester.pumpAndSettle();
      expect(find.text('旧密码不正确，请重新输入。'), findsOneWidget);
      await tester.enterText(find.byType(TextField), old);
      await tester.tap(find.text('验证旧密码'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('新密码')), next);
      await tester.enterText(
        find.byKey(const ValueKey('再次输入新密码')),
        'different',
      );
      await tester.tap(find.text('保存新密码'));
      await tester.pumpAndSettle();
      expect(find.text('两次输入的新密码不一致。'), findsOneWidget);
      expect(book.verifyPassword(old), isTrue);
      await tester.enterText(find.byKey(const ValueKey('再次输入新密码')), next);
      await tester.tap(find.text('保存新密码'));
      await tester.pumpAndSettle();
      expect(find.text('设置'), findsOneWidget);
      expect(book.verifyPassword(next), isTrue);
      expect(book.verifyPassword(old), isFalse);
    },
  );
}
