import 'package:flutter/material.dart';
import '../core/book.dart';
import '../core/models.dart';
import '../shared/widgets.dart';
import 'ledger.dart';
import 'review.dart';

class Stocktake extends StatefulWidget {
  const Stocktake({super.key});
  @override
  State<Stocktake> createState() => _StocktakeState();
}

class _StocktakeState extends State<Stocktake> {
  final name = TextEditingController(),
      amount = TextEditingController(),
      category = TextEditingController(),
      institution = TextEditingController(),
      rate = TextEditingController();
  String? editing, error;
  bool fresh = true, debt = false, loaded = false, dirty = false;
  DateTime? due;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!loaded) {
      loaded = true;
      final b = BookScope.of(context);
      load(
        b.draft.where((e) => e.name == '活期存款').firstOrNull ??
            b.draft.firstOrNull,
      );
    }
  }

  @override
  void dispose() {
    for (final k in [name, amount, category, institution, rate]) {
      k.dispose();
    }
    super.dispose();
  }

  void load(Entry? e) {
    editing = e?.id;
    fresh = e == null;
    debt = e?.debt ?? false;
    name.text = e?.name ?? '';
    amount.text = e == null ? '' : decimal(e.cents);
    category.text = e?.category ?? '';
    institution.text = e?.institution ?? '';
    rate.text = e?.rate ?? '';
    due = DateTime.tryParse(e?.due ?? '');
    dirty = false;
    error = null;
  }

  bool save(Book book) {
    final n = name.text.trim(), v = parseCents(amount.text);
    if (n.isEmpty || v == null) {
      setState(() => error = '请填写条目名称与非负余额，金额最多保留两位小数。');
      return false;
    }
    if (rate.text.isNotEmpty && (parseCents(rate.text) == null)) {
      setState(() => error = '年利率须为非负数，最多保留两位小数。');
      return false;
    }
    if (book.draft.any((e) => e.id != editing && e.name == n)) {
      setState(() => error = '请用不同名称区分条目，例如「工资卡」和「备用金」。');
      return false;
    }
    final e = Entry(
      id: editing ?? Entry.newId(),
      name: n,
      cents: v,
      debt: debt,
      category: category.text.trim().isEmpty ? n : category.text.trim(),
      institution: institution.text.trim(),
      due: due == null ? '' : day(due!),
      rate: rate.text.trim(),
    );
    try {
      book.saveEntry(e);
      editing = e.id;
      dirty = false;
      return true;
    } catch (_) {
      setState(() => error = '草稿保存失败，请重试。');
      return false;
    }
  }

  void select(Book b, String id) {
    if (dirty && !save(b)) return;
    setState(() => load(b.draft.where((e) => e.id == id).firstOrNull));
  }

  @override
  Widget build(BuildContext c) {
    final b = BookScope.of(c);
    return Scaffold(
      appBar: AppBar(title: const Text('盘点一次')),
      body: PageBody(
        children: [
          Picker<String>(
            label: '选择条目',
            value: editing ?? 'new',
            options: {for (final e in b.draft) e.id: e.name, 'new': '＋ 添加新条目'},
            onChanged: (id) => select(b, id),
          ),
          if (fresh) ...[
            TextField(
              controller: name,
              maxLength: 40,
              onChanged: (_) => dirty = true,
              decoration: const InputDecoration(labelText: '条目名称'),
            ),
            Choices<bool>(
              options: const {false: '资产', true: '负债'},
              value: debt,
              onChanged: (v) => setState(() {
                debt = v;
                dirty = true;
              }),
            ),
            TextField(
              controller: category,
              onChanged: (_) => dirty = true,
              decoration: const InputDecoration(labelText: '分类（可沿用条目名称）'),
            ),
            TextField(
              controller: institution,
              onChanged: (_) => dirty = true,
              decoration: const InputDecoration(labelText: '所属机构或平台（选填）'),
            ),
          ],
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => dirty = true,
            decoration: const InputDecoration(labelText: '当前余额（元）'),
          ),
          ExpansionTile(
            title: const Text('到期日与约定年利率（选填）'),
            children: [
              DataRowLink(
                '到期日',
                due == null ? '选择日期' : day(due!),
                onTap: () async {
                  final d = await showDatePicker(
                    context: c,
                    initialDate: due ?? DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2200),
                  );
                  if (d != null && mounted) {
                    setState(() {
                      due = d;
                      dirty = true;
                    });
                  }
                },
              ),
              if (due != null)
                TextButton(
                  onPressed: () => setState(() {
                    due = null;
                    dirty = true;
                  }),
                  child: const Text('清除日期'),
                ),
              TextField(
                controller: rate,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => dirty = true,
                decoration: const InputDecoration(labelText: '约定年利率（%）'),
              ),
            ],
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(c).colorScheme.error),
            ),
          OutlinedButton(
            onPressed: () {
              final wasNew = fresh;
              if (!save(b)) return;
              final i = b.draft.indexWhere((e) => e.id == editing);
              setState(
                () => load(
                  wasNew || i == b.draft.length - 1 ? null : b.draft[i + 1],
                ),
              );
              message(c, '已保存到本期草稿');
            },
            child: const Text('保存并继续填'),
          ),
          FilledButton(
            onPressed: () async {
              if (fresh && !dirty && b.draft.isNotEmpty || save(b)) {
                final committed = await openPage<Snapshot>(
                  c,
                  const ConfirmStocktake(),
                );
                if (committed != null && c.mounted) {
                  Navigator.of(c).pop(committed);
                }
              }
            },
            child: const Text('核对本期'),
          ),
          ExpansionTile(
            title: Text('本期草稿（${b.draft.length} 项）'),
            subtitle: const Text('未改余额自动沿用'),
            children: [
              for (final e in b.draft)
                DataRowLink(
                  e.name,
                  money(e.cents),
                  subtitle: changeLabel(e, b.latest?.find(e.id)),
                  onTap: () => select(b, e.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class ConfirmStocktake extends StatefulWidget {
  const ConfirmStocktake({super.key});
  @override
  State<ConfirmStocktake> createState() => _ConfirmState();
}

class _ConfirmState extends State<ConfirmStocktake> {
  bool submitted = false;
  @override
  Widget build(BuildContext c) {
    final b = BookScope.of(c),
        old = b.latest,
        rows = b.draft,
        changed = rows.where((e) => !e.same(old?.find(e.id))).toList(),
        net = rows.fold(0, (n, e) => n + e.contribution);
    return Scaffold(
      appBar: AppBar(title: const Text('核对本期盘点')),
      body: PageBody(
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('本期净资产'),
                Text(money(net), style: Theme.of(c).textTheme.headlineMedium),
                Text(old == null ? '首次盘点' : '较上期 ${signed(net - old.net)} 元'),
              ],
            ),
          ),
          Text('${changed.length} 项更新 · ${rows.length - changed.length} 项沿用'),
          for (final e in changed)
            DataRowLink(
              e.name,
              money(e.cents),
              subtitle: old?.find(e.id) == null
                  ? '首次记录'
                  : '上期 ${money(old!.find(e.id)!.cents)}',
            ),
          if (rows.length > changed.length)
            ExpansionTile(
              title: const Text('沿用上期的条目'),
              children: [
                for (final e in rows.where((e) => e.same(old?.find(e.id))))
                  DataRowLink(e.name, money(e.cents)),
              ],
            ),
          FilledButton(
            onPressed: submitted
                ? null
                : () {
                    setState(() => submitted = true);
                    try {
                      final saved = b.commit();
                      Navigator.pop(c, saved);
                    } catch (_) {
                      setState(() => submitted = false);
                      message(c, '提交失败，草稿已保留。请重新打开账本再试。');
                    }
                  },
            child: const Text('提交并看回执'),
          ),
        ],
      ),
    );
  }
}

Future<void> startStocktake(BuildContext c) async {
  final saved = await openPage<Snapshot>(c, const Stocktake());
  if (saved != null && c.mounted) await openPage(c, Receipt(saved));
}
