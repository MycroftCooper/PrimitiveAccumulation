import 'package:flutter/material.dart';
import '../core/book.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../shared/widgets.dart';
import '../shared/pig_bank.dart';
import '../shared/charts.dart';
import 'ledger.dart';
import 'review.dart';

class GrowthPage extends StatefulWidget {
  const GrowthPage({super.key});
  @override
  State<GrowthPage> createState() => _GrowthState();
}

class _GrowthState extends State<GrowthPage> {
  bool previous = false;
  int? radarId;
  @override
  Widget build(BuildContext c) {
    final book = BookScope.of(c),
        all = book.periods,
        last = book.latest,
        p = WealthColors.of(c);
    final s = previous && last != null ? (book.previous(last) ?? last) : last;
    final prior = s == null ? null : book.previous(s),
        amount = s?.net ?? 0,
        g = book.goal;
    final radar = all.where((s) => s.id == radarId).firstOrNull ?? last;
    final byDay = <String, Snapshot>{for (final s in all) day(s.time): s};
    return PageBody(
      children: [
        const SectionTitle('我的存钱罐'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [p.stage, p.stageGlow],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s == null ? '净资产起点' : '${day(s.time)} · 净资产',
                      style: TextStyle(color: p.onStage),
                    ),
                  ),
                  if (all.length > 1)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: p.ink,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          for (final opt in [true, false])
                            TextButton(
                              onPressed: () => setState(() => previous = opt),
                              style: TextButton.styleFrom(
                                foregroundColor: opt == previous
                                    ? p.gold
                                    : p.onStage,
                                minimumSize: const Size(44, 44),
                                padding: EdgeInsets.zero,
                              ),
                              child: Text(opt ? '上期' : '本期'),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
              FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  s == null ? '待盘点' : money(amount),
                  style: TextStyle(
                    color: p.onStage,
                    fontSize: 40,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                prior == null
                    ? (s == null ? '记下第一笔，开始积累。' : '第一份盘点')
                    : '较上期 ${signed(amount - prior.net)} 元',
                style: TextStyle(color: p.onStage),
              ),
              PigBank(amount),
            ],
          ),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                g?.name ?? '我的财富目标',
                action: TextButton(
                  onPressed: last == null
                      ? null
                      : () => openPage(c, const GoalEditor()),
                  child: const Text('设置目标'),
                ),
              ),
              if (g != null) ...[
                Text('目标 ${money(g.amount)}　${percent(amount, g.amount)}'),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: (amount / g.amount).clamp(0, 1),
                  semanticsLabel: '目标进度',
                ),
                const SizedBox(height: 6),
                Text(
                  amount >= g.amount
                      ? '已达到目标，超出 ${money(amount - g.amount)}'
                      : '还差 ${money(g.amount - amount)}',
                ),
                if (g.deadline.isNotEmpty) Text('目标日 ${g.deadline}'),
              ] else
                Text(last == null ? '盘点后可以设置第一个目标。' : '给要攒的钱起个名字，设一个目标金额。'),
            ],
          ),
        ),
        if (last == null)
          const Blank('开始第一份账本', '点下方「盘点一次」，从一笔资产或负债开始。')
        else ...[
          SectionTitle(
            '积累趋势',
            action: TextButton(
              onPressed: () => openPage(c, Receipt(last)),
              child: const Text('本期回执'),
            ),
          ),
          BalanceChart('净资产', [
            for (final s in byDay.values)
              BalancePoint(s, s.net, () => openPeriod(c, s)),
          ], calendar: true),
          const SectionTitle('资产占比雷达图'),
          Picker<int>(
            label: '查看盘点',
            value: radar!.id,
            options: {for (final s in all.reversed) s.id: s.label},
            onChanged: (id) => setState(() => radarId = id),
          ),
          Panel(child: _radar(c, book, radar)),
        ],
      ],
    );
  }

  Widget _radar(BuildContext c, Book book, Snapshot now) {
    final prev = book.previous(now);
    final assets = now.entries.where((e) => !e.debt).toList();
    final keys = assets.map((e) => e.category).toSet().toList();
    final condensed = keys.length > 6;
    final groups = condensed ? [...keys.take(5), '其余分类合计'] : keys;
    bool matches(Entry e, String k) => condensed && k == '其余分类合计'
        ? !keys.take(5).contains(e.category)
        : e.category == k;
    final compare = <String, double>{};
    final parts = <ChartValue>[];
    for (final k in groups) {
      final rows = assets.where((e) => matches(e, k)).toList();
      if (prev != null && prev.total(false) > 0) {
        compare[k] =
            prev.entries
                .where((e) => !e.debt && matches(e, k))
                .fold(0, (n, e) => n + e.cents) /
            prev.total(false);
      }
      parts.add(
        ChartValue(
          k,
          rows.fold(0, (n, e) => n + e.cents),
          seriesColor(c, parts.length),
          () {
            if (rows.length == 1) {
              openEntry(c, now, rows.first);
              return;
            }
            openPage(
              c,
              Scaffold(
                appBar: AppBar(title: Text(k)),
                body: PageBody(
                  children: [
                    Text(now.label),
                    for (final e in rows)
                      DataRowLink(
                        e.name,
                        money(e.cents),
                        onTap: () => openEntry(c, now, e),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }
    return RadarChart(parts, compare);
  }
}

class GoalEditor extends StatefulWidget {
  const GoalEditor({super.key});
  @override
  State<GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<GoalEditor> {
  final name = TextEditingController(), amount = TextEditingController();
  int? base;
  DateTime? due;
  String? error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (base != null) return;
    final book = BookScope.of(context), g = book.goal;
    name.text = g?.name ?? '我的第一个 100 万';
    amount.text = decimal(g?.amount ?? 100000000);
    base = g?.baseId ?? book.latest!.id;
    due = DateTime.tryParse(g?.deadline ?? '');
  }

  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final book = BookScope.of(c);
    return Scaffold(
      appBar: AppBar(title: const Text('设置财富目标')),
      body: PageBody(
        children: [
          TextField(
            controller: name,
            maxLength: 32,
            decoration: const InputDecoration(labelText: '目标名称'),
          ),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '目标净资产（元）'),
          ),
          Picker<int>(
            label: '起点盘点',
            value: base!,
            options: {
              for (final s in book.periods.reversed)
                s.id: '${s.label} · ${money(s.net)}',
            },
            onChanged: (v) => setState(() => base = v),
          ),
          DataRowLink(
            '目标日期',
            due == null ? '选填' : day(due!),
            onTap: () async {
              final d = await showDatePicker(
                context: c,
                initialDate: due ?? DateTime.now(),
                firstDate: DateTime(1900),
                lastDate: DateTime(2200),
              );
              if (d != null && mounted) setState(() => due = d);
            },
          ),
          if (due != null)
            TextButton(
              onPressed: () => setState(() => due = null),
              child: const Text('清除日期'),
            ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(c).colorScheme.error),
            ),
          FilledButton(
            onPressed: () {
              final s = book.periods.firstWhere((s) => s.id == base),
                  v = parseCents(amount.text);
              if (name.text.trim().isEmpty ||
                  v == null ||
                  v <= 0 ||
                  v <= s.net) {
                setState(() => error = '请填写名称，目标金额须大于零且高于起点 ${money(s.net)}。');
                return;
              }
              if (due != null && day(due!).compareTo(day(s.time)) < 0) {
                setState(() => error = '目标日期须在起点当日或之后。');
                return;
              }
              try {
                book.setGoal(
                  WealthGoal(
                    name.text.trim(),
                    v,
                    s.id,
                    due == null ? '' : day(due!),
                  ),
                );
                Navigator.pop(c);
              } catch (_) {
                setState(() => error = '保存失败，请重试。');
              }
            },
            child: const Text('保存目标'),
          ),
        ],
      ),
    );
  }
}
