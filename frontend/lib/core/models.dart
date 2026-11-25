import 'dart:math';
import 'package:intl/intl.dart';

final _number = NumberFormat('#,##0.##', 'en_US');
String money(int cents) => '¥${_number.format(cents / 100)}';
String signed(int cents) =>
    '${cents > 0 ? '+' : ''}${_number.format(cents / 100)}';
String percent(int value, int total) =>
    total > 0 ? '${(value * 100 / total).toStringAsFixed(1)}%' : '—';
String day(DateTime value) => DateFormat('yyyy-MM-dd').format(value.toLocal());
String decimal(int cents) =>
    (cents / 100).toStringAsFixed(cents % 100 == 0 ? 0 : 2);
int? parseCents(String text) {
  final s = text.trim();
  if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(s)) return null;
  final parts = s.split('.');
  return int.parse(parts.first) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0')));
}

class Entry {
  final String id, name, category, institution, due, rate;
  final bool debt;
  final int cents;
  const Entry({
    required this.id,
    required this.name,
    required this.cents,
    required this.category,
    this.debt = false,
    this.institution = '',
    this.due = '',
    this.rate = '',
  });
  int get contribution => debt ? -cents : cents;
  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
  bool same(Entry? old) =>
      old != null &&
      cents == old.cents &&
      due == old.due &&
      rate == old.rate &&
      name == old.name &&
      category == old.category &&
      institution == old.institution &&
      debt == old.debt;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'cents': cents,
    'category': category,
    'debt': debt,
    'institution': institution,
    'due': due,
    'rate': rate,
  };
  factory Entry.fromJson(Map<String, dynamic> m) => Entry(
    id: m['id'],
    name: m['name'],
    cents: m['cents'],
    category: m['category'],
    debt: m['debt'],
    institution: m['institution'],
    due: m['due'],
    rate: m['rate'],
  );
}

class Snapshot {
  final int id;
  final DateTime time;
  final List<Entry> entries;
  Snapshot(this.id, this.time, List<Entry> items)
    : entries = List.unmodifiable(items);
  int get net => entries.fold(0, (n, e) => n + e.contribution);
  int total(bool debt) =>
      entries.where((e) => e.debt == debt).fold(0, (n, e) => n + e.cents);
  Entry? find(String id) => entries.where((e) => e.id == id).firstOrNull;
  String get label => '${day(time)} · 第 $id 期';
}

class WealthGoal {
  final String name, deadline;
  final int amount, baseId;
  const WealthGoal(this.name, this.amount, this.baseId, this.deadline);
  Map<String, dynamic> toJson() => {
    'name': name,
    'amount': amount,
    'base': baseId,
    'deadline': deadline,
  };
  factory WealthGoal.fromJson(Map<String, dynamic> m) =>
      WealthGoal(m['name'], m['amount'], m['base'], m['deadline']);
}
