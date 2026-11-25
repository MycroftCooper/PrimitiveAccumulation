import 'package:flutter/material.dart';
import '../core/book.dart';
import '../core/models.dart';
import '../shared/charts.dart';
import '../shared/widgets.dart';
import 'review.dart';

void openPeriod(BuildContext c, Snapshot s) => openPage(
  c,
  Scaffold(
    appBar: AppBar(title: Text(s.label)),
    body: LedgerPage(initial: s),
  ),
);
void openEntry(BuildContext c, Snapshot s, Entry e) =>
    openPage(c, EntryDetails(s, e));

class LedgerPage extends StatefulWidget {
  final Snapshot? initial;
  final String? initialItem;
  const LedgerPage({super.key, this.initial, this.initialItem});
  @override
  State<LedgerPage> createState() => _LedgerState();
}

class _LedgerState extends State<LedgerPage> {
  late bool byItem = widget.initialItem != null;
  bool chartMix = false, debt = false;
  late int? periodId = widget.initial?.id;
  late String? itemId = widget.initialItem;
  @override
  Widget build(BuildContext c) {
    final book = BookScope.of(c), all = book.periods, last = book.latest;
    if (last == null) {
      return const PageBody(
        children: [SectionTitle('账本'), Blank('你的第一期账本', '点「盘点一次」，记录第一笔资产或负债。')],
      );
    }
    final entry = last.find(itemId ?? '') ?? last.entries.first;
    final available = byItem
        ? all.where((s) => s.find(entry.id) != null).toList()
        : all;
    final s =
        available.where((v) => v.id == periodId).firstOrNull ?? available.last;
    final before = book.previous(s);
    final periodPicker = Picker<int>(
      label: '盘点期次',
      value: s.id,
      options: {for (final p in available.reversed) p.id: p.label},
      onChanged: (v) => setState(() => periodId = v),
    );
    final itemRows = available.reversed.map(
      (p) => DataRowLink(
        p.label,
        money(p.find(entry.id)!.cents),
        onTap: () => openEntry(c, p, p.find(entry.id)!),
      ),
    );
    final kind = byItem ? entry.debt : debt && s.entries.any((e) => e.debt);
    final sameKind = s.entries.where((e) => e.debt == kind).toList();
    final focus = s.find(entry.id);
    final kindName = kind ? '负债' : '资产';
    List<ChartValue> segments() {
      ChartValue value(Entry e) => ChartValue(
        e.name,
        e.cents,
        seriesColor(c, last.entries.indexWhere((v) => v.id == e.id)),
        () => openEntry(c, s, e),
      );
      if (!byItem) return sameKind.map(value).toList();
      final others = sameKind.where((e) => e.id != entry.id).toList();
      return [
        value(focus!),
        ChartValue(
          '其余$kindName',
          others.fold(0, (n, e) => n + e.cents),
          Theme.of(c).colorScheme.outline,
          () => openPage(
            c,
            Scaffold(
              appBar: AppBar(title: Text('其余$kindName')),
              body: PageBody(
                children: [
                  Text(s.label),
                  if (others.isEmpty) const Text('本期仅记录了这一项。'),
                  for (final e in others)
                    DataRowLink(
                      e.name,
                      money(e.cents),
                      onTap: () => openEntry(c, s, e),
                    ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    return PageBody(
      children: [
        const SectionTitle('账本'),
        Choices<bool>(
          value: byItem,
          options: const {false: '按期查', true: '按条目查'},
          onChanged: (v) => setState(() => byItem = v),
        ),
        if (byItem) ...[
          Picker<String>(
            label: '条目',
            value: entry.id,
            options: {for (final e in last.entries) e.id: e.name},
            onChanged: (v) => setState(() => itemId = v),
          ),
          Choices<bool>(
            value: chartMix,
            options: const {false: '余额走势', true: '构成占比'},
            onChanged: (v) => setState(() => chartMix = v),
          ),
          if (chartMix) ...[
            periodPicker,
            ShareChart('${entry.name}占总$kindName', segments()),
          ] else
            BalanceChart('${entry.name}余额走势', [
              for (final p in available)
                BalancePoint(
                  p,
                  p.find(entry.id)!.cents,
                  () => openEntry(c, p, p.find(entry.id)!),
                ),
            ]),
          const SectionTitle('历次余额'),
          ...itemRows,
        ] else ...[
          periodPicker,
          SectionTitle(
            '净资产 ${money(s.net)}',
            action: TextButton(
              onPressed: () => openPage(c, Receipt(s)),
              child: const Text('本期回执'),
            ),
          ),
          if (s.entries.any((e) => e.debt))
            Choices<bool>(
              value: kind,
              options: const {false: '资产', true: '负债'},
              onChanged: (v) => setState(() => debt = v),
            ),
          ShareChart('$kindName构成', segments()),
          const SectionTitle('本期明细'),
          for (final e in s.entries)
            DataRowLink(
              e.name,
              money(e.cents),
              subtitle:
                  '${e.debt ? "负债" : "资产"} · ${changeLabel(e, before?.find(e.id))}',
              onTap: () => openEntry(c, s, e),
            ),
        ],
      ],
    );
  }
}

String changeLabel(Entry e, Entry? prev) => prev == null
    ? '首次记录'
    : e.same(prev)
    ? '沿用上期'
    : e.cents == prev.cents
    ? '条款更新'
    : '余额更新';

class EntryDetails extends StatelessWidget {
  final Snapshot snapshot;
  final Entry entry;
  const EntryDetails(this.snapshot, this.entry, {super.key});
  @override
  Widget build(BuildContext c) {
    final book = BookScope.of(c),
        prev = book.previous(snapshot)?.find(entry.id);
    return Scaffold(
      appBar: AppBar(title: Text(entry.name)),
      body: PageBody(
        children: [
          Text(snapshot.label),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${entry.debt ? "负债" : "资产"} · ${entry.category}'),
                Text(
                  money(entry.cents),
                  style: Theme.of(c).textTheme.headlineLarge,
                ),
              ],
            ),
          ),
          DataRowLink('上期余额', prev == null ? '—' : money(prev.cents)),
          DataRowLink('本期余额', money(entry.cents)),
          if (entry.institution.isNotEmpty)
            DataRowLink('所属机构', entry.institution),
          if (entry.due.isNotEmpty || prev?.due.isNotEmpty == true)
            DataRowLink(
              '到期日',
              entry.due.isEmpty ? '—' : entry.due,
              subtitle: '上期 ${prev?.due ?? "—"}',
            ),
          if (entry.rate.isNotEmpty || prev?.rate.isNotEmpty == true)
            DataRowLink(
              '约定年利率',
              entry.rate.isEmpty ? '—' : '${entry.rate}%',
              subtitle:
                  '上期 ${prev?.rate.isNotEmpty == true ? "${prev!.rate}%" : "—"}',
            ),
          Text(
            book.previous(snapshot) == null
                ? '第一份盘点，作为起点。'
                : '本项对净资产的账面影响为 ${signed(entry.contribution - (prev?.contribution ?? 0))} 元。',
          ),
          OutlinedButton(
            onPressed: () => openPeriod(c, snapshot),
            child: const Text('查看该期全部明细'),
          ),
          TextButton(
            onPressed: () => openPage(
              c,
              Scaffold(
                appBar: AppBar(title: const Text('历次余额')),
                body: LedgerPage(initial: snapshot, initialItem: entry.id),
              ),
            ),
            child: const Text('查这项的历次余额'),
          ),
        ],
      ),
    );
  }
}
