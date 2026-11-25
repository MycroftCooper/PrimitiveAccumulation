import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sqlite3/sqlite3.dart';
import 'models.dart';

class Book extends ChangeNotifier {
  final Database _db;
  final bool demo;
  final List<Snapshot> _periods = [];
  List<Snapshot> get periods => List.unmodifiable(_periods);
  Snapshot? get latest => _periods.lastOrNull;
  List<Entry> draft = [];
  String? _savedDraft;
  WealthGoal? goal;
  ThemeMode mode = ThemeMode.system;
  String skin = 'grove';
  Book._(this._db, this.demo) {
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
    for (final row in _db.select('SELECT * FROM snapshots ORDER BY id')) {
      _periods.add(
        Snapshot(
          row['id'],
          DateTime.fromMicrosecondsSinceEpoch(row['time']),
          _decodeItems(row['entries']),
        ),
      );
    }
    final prefs = {
      for (final row in _db.select('SELECT * FROM preferences'))
        row['key']: row['value'],
    };
    if (prefs['goal'] != null) {
      goal = WealthGoal.fromJson(jsonDecode(prefs['goal']));
    }
    skin = prefs['skin'] ?? 'grove';
    mode =
        ThemeMode.values.where((m) => m.name == prefs['mode']).firstOrNull ??
        ThemeMode.system;
    _savedDraft = prefs['draft'];
    draft = _savedDraft == null
        ? [...?latest?.entries]
        : _decodeItems(prefs['draft']);
  }
  static List<Entry> _decodeItems(String json) =>
      (jsonDecode(json) as List).map((m) => Entry.fromJson(m)).toList();
  static String _encodeItems(List<Entry> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());
  factory Book.open(String path, String password) {
    final db = sqlite3.open(path);
    try {
      final key = password.replaceAll("'", "''");
      db.execute("PRAGMA key='$key'");
      // Verify the cipher before creating tables. An existing file needs its key first.
      db.select('SELECT sqlite3mc_version()');
      db.select('SELECT count(*) FROM sqlite_master');
      db.execute('PRAGMA busy_timeout = 3000');
      return Book._(db, false);
    } catch (_) {
      db.close();
      rethrow;
    }
  }
  factory Book.example() {
    final book = Book._(sqlite3.openInMemory(), true);
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
  void saveEntry(Entry entry) {
    final rows = [...draft];
    final i = rows.indexWhere((e) => e.id == entry.id);
    if (i < 0) {
      rows.add(entry);
    } else {
      rows[i] = entry;
    }
    final encoded = _encodeItems(rows);
    _db.execute('BEGIN IMMEDIATE');
    try {
      _checkBase();
      _pref('draft', encoded);
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
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
    _db.execute('BEGIN IMMEDIATE');
    late Snapshot snap;
    try {
      _checkBase();
      _db.execute('INSERT INTO snapshots(time,entries) VALUES(?,?)', [
        time.microsecondsSinceEpoch,
        _encodeItems(draft),
      ]);
      snap = Snapshot(_db.lastInsertRowId, time, draft);
      _db.execute("DELETE FROM preferences WHERE key='draft'");
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    _periods.add(snap);
    _savedDraft = null;
    draft = [...snap.entries];
    notifyListeners();
    return snap;
  }

  void setGoal(WealthGoal value) {
    _pref('goal', jsonEncode(value.toJson()));
    goal = value;
    notifyListeners();
  }

  String note(int id) =>
      _db.select('SELECT text FROM notes WHERE snapshot=?', [
        id,
      ]).firstOrNull?['text'] ??
      '';
  void saveNote(int id, String value) {
    _db.execute(
      'INSERT INTO notes VALUES(?,?) ON CONFLICT(snapshot) DO UPDATE SET text=excluded.text',
      [id, value.trim()],
    );
    notifyListeners();
  }

  void appearance(ThemeMode value, String palette) {
    _db.execute('BEGIN');
    try {
      _pref('mode', value.name);
      _pref('skin', palette);
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
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
