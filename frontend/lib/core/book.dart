import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sqlite3/sqlite3.dart';
import 'models.dart';
import 'backup.dart';

class Book extends ChangeNotifier {
  Database _db;
  final String? _path;
  bool get demo => _path == null;
  static const minPasswordLength = 6;
  final List<Snapshot> _periods = [];
  List<Snapshot> get periods => List.unmodifiable(_periods);
  Snapshot? get latest => _periods.lastOrNull;
  List<Entry> draft = [];
  String? _savedDraft;
  WealthGoal? goal;
  ThemeMode mode = ThemeMode.system;
  String skin = 'grove';
  Book._(this._db, this._path) {
    _db.execute('PRAGMA foreign_keys=ON');
    _db.execute(
      'CREATE TABLE IF NOT EXISTS snapshots(id INTEGER PRIMARY KEY, time INTEGER NOT NULL, entries TEXT NOT NULL)',
    );
    _db.execute(
      'CREATE TABLE IF NOT EXISTS preferences(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    _db.execute(
      'CREATE TABLE IF NOT EXISTS notes(snapshot INTEGER PRIMARY KEY REFERENCES snapshots(id), text TEXT NOT NULL)',
    );
    _db.execute(
      'CREATE TABLE IF NOT EXISTS restore_state(id INTEGER PRIMARY KEY CHECK(id=1), generation INTEGER NOT NULL)',
    );
    _db.execute('INSERT OR IGNORE INTO restore_state VALUES(1,0)');
    _db.execute('BEGIN');
    try {
      _generation = _storedGeneration;
      _apply(_readData());
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  int _generation = 0;
  int get _storedGeneration => _db
      .select('SELECT generation FROM restore_state WHERE id=1')
      .single['generation'];

  void _apply(BackupData data) {
    _periods
      ..clear()
      ..addAll(data.snapshots);
    final prefs = data.preferences;
    final savedGoal = prefs['goal'];
    goal = savedGoal == null
        ? null
        : WealthGoal.fromJson(jsonDecode(savedGoal));
    skin = prefs['skin'] ?? 'grove';
    mode =
        ThemeMode.values.where((m) => m.name == prefs['mode']).firstOrNull ??
        ThemeMode.system;
    _savedDraft = prefs['draft'];
    draft = _savedDraft == null
        ? [...?latest?.entries]
        : _decodeItems(_savedDraft!);
  }

  static List<Entry> _decodeItems(String json) =>
      (jsonDecode(json) as List).map((m) => Entry.fromJson(m)).toList();
  static String _encodeItems(List<Entry> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());
  static String _hexPassword(String password) => utf8
      .encode(password)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  static Database _openKeyed(String path, String password, OpenMode mode) {
    if (password.isEmpty) throw const FormatException('请输入账本密码。');
    final db = sqlite3.open(path, mode: mode);
    try {
      db.execute("PRAGMA hexkey='${_hexPassword(password)}'");
      db.select('SELECT sqlite3mc_version()');
      db.execute('PRAGMA busy_timeout = 3000');
      db.select('SELECT count(*) FROM sqlite_master');
      return db;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  factory Book.open(String path, String password) {
    final db = _openKeyed(path, password, OpenMode.readWriteCreate);
    try {
      return Book._(db, path);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  String get _personalPath => _path ?? (throw StateError('体验账本没有解锁密码。'));

  bool verifyPassword(String password) {
    if (password.isEmpty) return false;
    try {
      _openKeyed(_personalPath, password, OpenMode.readOnly).close();
      return true;
    } on SqliteException catch (e) {
      if (e.resultCode == SqlError.SQLITE_NOTADB) return false;
      rethrow;
    }
  }

  void changePassword(String oldPassword, String newPassword) {
    if (newPassword.length < minPasswordLength || newPassword == oldPassword) {
      throw const FormatException('请使用与旧密码不同、至少 6 位的新密码。');
    }
    // Authenticate the on-disk key again when saving, including after another
    // window has rotated it since the first step of the form.
    final db = _openKeyed(_personalPath, oldPassword, OpenMode.readWrite);
    try {
      db.execute('PRAGMA foreign_keys=ON');
      db.execute('PRAGMA locking_mode=EXCLUSIVE');
      db.execute('BEGIN EXCLUSIVE');
      db.select('SELECT generation FROM restore_state WHERE id=1');
      db.execute('COMMIT');
      // Exclusive mode retains the lock across COMMIT. Rekey manages its own
      // transaction; switching back to NORMAL releases the lock on next access.
      db.execute('PRAGMA locking_mode=NORMAL');
      final result = db.select(
        "PRAGMA hexrekey='${_hexPassword(newPassword)}'",
      );
      if (result.single.values.single != 'ok') throw StateError('更新账本密码失败。');
    } catch (_) {
      db.close();
      rethrow;
    }
    final previous = _db;
    _db = db;
    previous.close();
  }

  factory Book.example() {
    final book = Book._(sqlite3.openInMemory(), null);
    const names = ['定期存款', '中短债', '活期存款', '股票', '公积金'];
    List<Entry> sample(List<int> amounts) => List.generate(
      amounts.length,
      (i) => Entry(
        id: 'sample-$i',
        name: names[i],
        category: names[i],
        cents: amounts[i] * 100,
        due: i == 0
            ? '2027-11-28'
            : i == 1
            ? '2026-08-24'
            : '',
        rate: i == 0 ? '1.90' : '',
      ),
    );
    book.draft = sample([200000, 150000, 100000, 150000]);
    book._commitAt(DateTime(2026, 5, 15));
    book.draft = sample([200000, 150000, 82252, 253064, 27122]);
    book._commitAt(DateTime(2026, 7, 15));
    book.setGoal(const WealthGoal('我的第一个 100 万', 100000000, 1, ''));
    return book;
  }
  Snapshot? previous(Snapshot s) {
    final i = _periods.indexWhere((p) => p.id == s.id);
    return i > 0 ? _periods[i - 1] : null;
  }

  void _pref(String key, String value) => _db.execute(
    'INSERT INTO preferences VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, value],
  );
  void _write(void Function() action) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      if (_generation != _storedGeneration) {
        throw StateError('账本已在其他窗口恢复，请重新打开。');
      }
      action();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  // Both other connections and writes by this window invalidate a restore preview.
  ({int periodCount, (int, int) revision}) get restorePreview {
    final row = _db
        .select(
          'SELECT data_version, total_changes() AS changes, '
          '(SELECT count(*) FROM snapshots) AS periods FROM pragma_data_version',
        )
        .single;
    return (
      periodCount: row['periods'] as int,
      revision: (row['data_version'] as int, row['changes'] as int),
    );
  }

  (int, int) get revision => restorePreview.revision;

  BackupData _readData() => BackupData.fromJson({
    'snapshots': [
      for (final row in _db.select('SELECT * FROM snapshots ORDER BY id'))
        {
          'id': row['id'],
          'time': row['time'],
          'entries': jsonDecode(row['entries']),
        },
    ],
    'notes': {
      for (final row in _db.select('SELECT * FROM notes'))
        row['snapshot'].toString(): row['text'],
    },
    'preferences': {
      for (final row in _db.select('SELECT * FROM preferences'))
        row['key']: row['value'],
    },
  });

  BackupData exportData() {
    _db.execute('BEGIN');
    try {
      final result = _readData();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void restore(BackupData data, {required (int, int) expectedRevision}) {
    _write(() {
      if (expectedRevision != revision) throw StateError('账本已变化，请重新预览备份。');
      _db.execute('DELETE FROM notes');
      _db.execute('DELETE FROM snapshots');
      _db.execute('DELETE FROM preferences');
      for (final s in data.snapshots) {
        _db.execute('INSERT INTO snapshots(id,time,entries) VALUES(?,?,?)', [
          s.id,
          s.time.microsecondsSinceEpoch,
          _encodeItems(s.entries),
        ]);
      }
      for (final n in data.notes.entries) {
        _db.execute('INSERT INTO notes(snapshot,text) VALUES(?,?)', [
          n.key,
          n.value,
        ]);
      }
      for (final p in data.preferences.entries) {
        _pref(p.key, p.value);
      }
      _db.execute(
        'UPDATE restore_state SET generation=generation+1 WHERE id=1',
      );
    });
    _generation++;
    _apply(data);
    notifyListeners();
  }

  void saveEntry(Entry entry) {
    final rows = [...draft];
    final i = rows.indexWhere((e) => e.id == entry.id);
    if (i < 0) {
      rows.add(entry);
    } else {
      rows[i] = entry;
    }
    final encoded = _encodeItems(rows);
    _write(() {
      _checkBase();
      _pref('draft', encoded);
    });
    _savedDraft = encoded;
    draft = rows;
    notifyListeners();
  }

  Snapshot commit() => _commitAt(DateTime.now());
  void _checkBase() {
    final last = _db.select('SELECT MAX(id) AS id FROM snapshots').single['id'];
    final saved = _db
        .select("SELECT value FROM preferences WHERE key='draft'")
        .firstOrNull?['value'];
    if (last != latest?.id || saved != _savedDraft) {
      throw StateError('其他窗口已修改账本，请重新打开后核对草稿。');
    }
  }

  Snapshot _commitAt(DateTime time) {
    if (draft.isEmpty) throw StateError('请先添加条目');
    late Snapshot snap;
    _write(() {
      _checkBase();
      _db.execute('INSERT INTO snapshots(time,entries) VALUES(?,?)', [
        time.microsecondsSinceEpoch,
        _encodeItems(draft),
      ]);
      snap = Snapshot(_db.lastInsertRowId, time, draft);
      _db.execute("DELETE FROM preferences WHERE key='draft'");
    });
    _periods.add(snap);
    _savedDraft = null;
    draft = [...snap.entries];
    notifyListeners();
    return snap;
  }

  void setGoal(WealthGoal value) {
    _write(() => _pref('goal', jsonEncode(value.toJson())));
    goal = value;
    notifyListeners();
  }

  String note(int id) =>
      _db.select('SELECT text FROM notes WHERE snapshot=?', [
        id,
      ]).firstOrNull?['text'] ??
      '';
  void saveNote(int id, String value) {
    _write(
      () => _db.execute(
        'INSERT INTO notes VALUES(?,?) ON CONFLICT(snapshot) DO UPDATE SET text=excluded.text',
        [id, value.trim()],
      ),
    );
    notifyListeners();
  }

  void appearance(ThemeMode value, String palette) {
    _write(() {
      _pref('mode', value.name);
      _pref('skin', palette);
    });
    mode = value;
    skin = palette;
    notifyListeners();
  }

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }
}

class BookScope extends InheritedNotifier<Book> {
  const BookScope({super.key, required Book book, required super.child})
    : super(notifier: book);
  static Book of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<BookScope>()!.notifier!;
}
