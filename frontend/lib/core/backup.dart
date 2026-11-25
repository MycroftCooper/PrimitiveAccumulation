import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'models.dart';

/// Version 1 stores a UTF-8 JSON ledger inside an authenticated binary envelope.
/// Header (AAD), 16-byte salt, then nonce | ciphertext | tag.
class BackupFile {
  static final _header = ascii.encode('PA-BACKUP:1\n');
  static const maxBytes = 32 * 1024 * 1024;

  static Future<SecretKey> _key(String password, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 600000,
    bits: 256,
  ).deriveKeyFromPassword(password: password, nonce: salt);

  static Future<Uint8List> encrypt(BackupData data, String password) =>
      Isolate.run(() async {
        final bytes = utf8.encode(jsonEncode(data.toJson()));
        if (bytes.length + _header.length + 44 > maxBytes) {
          throw const FormatException('账本超过当前单个备份文件的 32 MiB 上限。');
        }
        final random = Random.secure();
        final salt = List.generate(16, (_) => random.nextInt(256));
        final box = await AesGcm.with256bits().encrypt(
          bytes,
          secretKey: await _key(password, salt),
          aad: _header,
        );
        return (BytesBuilder(copy: false)
              ..add(_header)
              ..add(salt)
              ..add(box.concatenation()))
            .takeBytes();
      });

  static Future<BackupData> decrypt(Uint8List bytes, String password) =>
      Isolate.run(() async {
        final start = _header.length;
        if (bytes.length > maxBytes ||
            bytes.length < start + 44 ||
            !bytes.take(start).indexed.every((p) => p.$2 == _header[p.$1])) {
          throw const FormatException('文件格式或版本不受支持。请选择原始积累备份。');
        }
        final key = await _key(password, bytes.sublist(start, start + 16));
        final box = SecretBox.fromConcatenation(
          Uint8List.sublistView(bytes, start + 16),
          nonceLength: 12,
          macLength: 16,
        );
        try {
          final plain = await AesGcm.with256bits().decrypt(
            box,
            secretKey: key,
            aad: _header,
          );
          return BackupData.fromJson(jsonDecode(utf8.decode(plain)));
        } on SecretBoxAuthenticationError {
          throw const FormatException('备份密码有误，或文件已损坏。');
        }
      });
}

class BackupData {
  final List<Snapshot> snapshots;
  final Map<int, String> notes;
  final Map<String, String> preferences;
  BackupData._(
    List<Snapshot> rows,
    Map<int, String> comments,
    Map<String, String> prefs,
  ) : snapshots = List.unmodifiable(rows),
      notes = Map.unmodifiable(comments),
      preferences = Map.unmodifiable(prefs);

  Map<String, Object> toJson() => {
    'snapshots': [
      for (final s in snapshots)
        {
          'id': s.id,
          'time': s.time.microsecondsSinceEpoch,
          'entries': s.entries.map((e) => e.toJson()).toList(),
        },
    ],
    'notes': {for (final n in notes.entries) n.key.toString(): n.value},
    'preferences': preferences,
  };

  factory BackupData.fromJson(dynamic json) {
    const invalid = FormatException('备份中的账本数据不完整或无效。');
    List<Entry> entries(dynamic value) {
      final ids = <String>{};
      final result = <Entry>[];
      for (final row in value as List) {
        final entry = Entry.fromJson(row);
        if (entry.cents < 0 ||
            entry.id.isEmpty ||
            !ids.add(entry.id) ||
            entry.name.trim().isEmpty ||
            entry.category.trim().isEmpty) {
          throw invalid;
        }
        result.add(entry);
      }
      return result;
    }

    try {
      final snapshots = <Snapshot>[];
      final ids = <int>{};
      for (final row in json['snapshots'] as List) {
        final int id = row['id'];
        final items = entries(row['entries']);
        if (id <= 0 ||
            (snapshots.isNotEmpty && id <= snapshots.last.id) ||
            items.isEmpty) {
          throw invalid;
        }
        ids.add(id);
        snapshots.add(
          Snapshot(id, DateTime.fromMicrosecondsSinceEpoch(row['time']), items),
        );
      }
      final notes = <int, String>{};
      for (final n in (json['notes'] as Map).entries) {
        final id = int.parse(n.key);
        if (!ids.contains(id) || notes.containsKey(id)) throw invalid;
        notes[id] = n.value;
      }
      final prefs = Map<String, String>.from(json['preferences']);
      if (prefs.containsKey('draft')) entries(jsonDecode(prefs['draft']!));
      if (prefs.containsKey('goal')) {
        final goal = WealthGoal.fromJson(jsonDecode(prefs['goal']!));
        if (!ids.contains(goal.baseId) || goal.amount <= 0) throw invalid;
      }
      return BackupData._(snapshots, notes, prefs);
    } on TypeError {
      throw invalid;
    } on ArgumentError {
      throw invalid;
    }
  }
}
