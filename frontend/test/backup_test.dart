import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primitive_accumulation/core/backup.dart';
import 'package:primitive_accumulation/core/book.dart';
import 'package:primitive_accumulation/core/models.dart';

void main() {
  test(
    'encrypted file restores the complete ledger under a different local password',
    () async {
      final dir = Directory.systemTemp.createTempSync('wealth-backup-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final source = Book.example();
      addTearDown(source.dispose);
      source.appearance(ThemeMode.dark, 'dusk');
      source.saveNote(1, '回顾记录');
      source.saveEntry(
        const Entry(
          id: 'loan',
          name: '借款',
          category: '贷款',
          cents: 125,
          debt: true,
          institution: 'A',
        ),
      );
      final original = source.exportData();
      final file = File('${dir.path}/transfer.pabackup');
      const pass = 'test-备份🔑';
      await file.writeAsBytes(
        await BackupFile.encrypt(original, pass),
        flush: true,
      );
      final bytes = await file.readAsBytes();
      expect(utf8.decode(bytes, allowMalformed: true), isNot(contains('回顾记录')));
      final path = '${dir.path}/destination.db';
      final target = Book.open(path, 'destination-key');
      target.saveEntry(
        const Entry(id: 'old', name: '现金', category: '资产', cents: 123),
      );
      target.commit();
      final before = target.exportData().toJson();
      await expectLater(
        BackupFile.decrypt(bytes, 'incorrect'),
        throwsFormatException,
      );
      final corrupt = Uint8List.fromList(bytes);
      corrupt[corrupt.length - 1] ^= 1;
      await expectLater(
        BackupFile.decrypt(corrupt, pass),
        throwsFormatException,
      );
      expect(target.exportData().toJson(), before);
      final data = await BackupFile.decrypt(bytes, pass);
      target.restore(data, expectedRevision: target.revision);
      expect(target.exportData().toJson(), original.toJson());
      target.dispose();
      final opened = Book.open(path, 'destination-key');
      addTearDown(opened.dispose);
      expect(opened.periods.first.id, 1);
      expect(opened.note(1), '回顾记录');
      expect(opened.mode, ThemeMode.dark);
      expect(opened.draft.last.contribution, -125);
      expect(opened.goal!.baseId, 1);
      expect(opened.commit().net, original.snapshots.last.net - 125);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'replacement rejects stale previews and invalidates old windows even with matching snapshot IDs',
    () {
      final dir = Directory.systemTemp.createTempSync('wealth-restore-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/destination.db';
      final a = Book.open(path, 'secret'), b = Book.open(path, 'secret');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final empty = a.exportData(), before = a.revision;
      b.appearance(ThemeMode.dark, 'dusk');
      expect(
        () => a.restore(empty, expectedRevision: before),
        throwsStateError,
      );
      final current = a.exportData().toJson();
      expect(current['preferences'], containsPair('skin', 'dusk'));
      a.restore(empty, expectedRevision: a.revision);
      expect(a.skin, 'grove');
      expect(() => b.appearance(ThemeMode.light, 'dusk'), throwsStateError);
      expect(a.exportData().toJson(), empty.toJson());
    },
  );

  test('restore preview includes a snapshot committed by another window', () {
    final dir = Directory.systemTemp.createTempSync('wealth-preview-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/book.db';
    final reader = Book.open(path, 'test-key');
    final writer = Book.open(path, 'test-key');
    addTearDown(reader.dispose);
    addTearDown(writer.dispose);
    final original = reader.exportData();
    writer.saveEntry(
      const Entry(id: 'cash', name: '现金', category: '现金', cents: 100),
    );
    writer.commit();
    final preview = reader.restorePreview;
    expect(preview.periodCount, 1);
    writer.commit();
    expect(
      () => reader.restore(original, expectedRevision: preview.revision),
      throwsStateError,
    );
    expect(reader.restorePreview.periodCount, 2);
  });

  test(
    'foreign files, unsupported versions and broken snapshot references are refused',
    () async {
      await expectLater(
        BackupFile.decrypt(Uint8List(100), 'x'),
        throwsFormatException,
      );
      final book = Book.example();
      addTearDown(book.dispose);
      final json = book.exportData().toJson();
      json['notes'] = {'4': 'unknown period'};
      expect(() => BackupData.fromJson(json), throwsFormatException);
      json['notes'] = {};
      (json['snapshots'] as List).add((json['snapshots'] as List).first);
      expect(() => BackupData.fromJson(json), throwsFormatException);
    },
  );
}
