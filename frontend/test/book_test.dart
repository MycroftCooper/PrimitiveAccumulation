import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primitive_accumulation/core/book.dart';
import 'package:primitive_accumulation/core/models.dart';

void main() {
  test(
    'a stale window cannot overwrite a saved draft or append a stale snapshot',
    () {
      final dir = Directory.systemTemp.createTempSync('wealth-draft-test-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/test.sqlite';
      final first = Book.open(path, 'draft-test');
      final second = Book.open(path, 'draft-test');
      const entry = Entry(id: 'cash', name: '现金', cents: 100, category: '存款');
      first.saveEntry(entry);
      expect(() => second.saveEntry(entry), throwsStateError);
      first.commit();
      expect(() => second.saveEntry(entry), throwsStateError);
      first.dispose();
      second.dispose();
      final restored = Book.open(path, 'draft-test');
      expect(restored.latest!.net, 100);
      expect(restored.periods, hasLength(1));
      restored.dispose();
    },
  );
  test(
    'encrypted snapshots, drafts, notes and appearance survive reopening',
    () {
      final dir = Directory.systemTemp.createTempSync('wealth-sqlite-test-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/test.sqlite'), key = "local'test-key";
      var book = Book.open(file.path, key);
      const cash = Entry(
        id: 'cash',
        name: '测试现金',
        cents: 10001,
        category: '现金',
      );
      book.saveEntry(cash);
      final first = book.commit();
      book.saveEntry(
        const Entry(
          id: 'loan',
          name: '贷款',
          cents: 5000,
          debt: true,
          category: '贷款',
        ),
      );
      final second = book.commit();
      expect(first.net, 10001);
      expect(second.net, 5001);
      book.setGoal(WealthGoal('目标', 20000, first.id, ''));
      book.appearance(ThemeMode.dark, 'dusk');
      book.saveNote(second.id, '本期备注');
      book.saveEntry(
        const Entry(id: 'cash', name: '测试现金', cents: 10002, category: '现金'),
      );
      book.dispose();
      expect(
        utf8.decode(
          file.readAsBytesSync().take(16).toList(),
          allowMalformed: true,
        ),
        isNot(startsWith('SQLite format 3')),
      );
      expect(() => Book.open(file.path, 'wrong password'), throwsA(anything));
      book = Book.open(file.path, key);
      expect(book.periods.first.net, 10001);
      expect(book.latest!.net, 5001);
      expect(book.draft.first.cents, 10002);
      expect(book.goal!.baseId, first.id);
      expect(book.mode, ThemeMode.dark);
      expect(book.skin, 'dusk');
      expect(book.note(second.id), '本期备注');
      book.dispose();
    },
  );
  test(
    'cents use decimal input without rounding and demo accounts are isolated',
    () {
      expect(parseCents('0.01'), 1);
      expect(parseCents('1.999'), isNull);
      final a = Book.example(), b = Book.example();
      a.commit();
      expect(b.periods.length, 2);
      expect(b.latest!.net, 32000000);
      a.dispose();
      b.dispose();
    },
  );
}
